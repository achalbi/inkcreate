require "test_helper"

class Backups::ScheduleCaptureBackupTest < ActiveSupport::TestCase
  def build_user(email:, drive_ready: true, media_backups_enabled: true)
    user = User.create!(
      email: email,
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )

    if drive_ready
      user.update!(
        google_drive_connected_at: Time.current,
        google_drive_refresh_token: "refresh-token",
        google_drive_folder_id: "drive-root-folder"
      )
    end

    user.ensure_app_setting!.update!(
      backup_enabled: true,
      backup_provider: "google_drive",
      privacy_options: user.ensure_app_setting!.privacy_options.merge("include_photos_in_backups" => media_backups_enabled)
    )

    user
  end

  def build_capture(user:, title:)
    user.captures.create!(
      title: title,
      original_filename: "#{title.parameterize}.jpg",
      content_type: "image/jpeg",
      byte_size: 1024,
      storage_bucket: "test-bucket",
      storage_object_key: "users/#{user.id}/uploads/test/#{title.parameterize}.jpg",
      page_type: "blank",
      backup_status: :local_only
    )
  end

  test "schedules a pending capture package backup with planned package metadata" do
    user = build_user(email: "schedule-capture-backup@example.com")
    capture = build_capture(user: user, title: "Sprint review")
    enqueued_drive_sync_ids = []
    events = []

    Async::Dispatcher.stub(:enqueue_drive_export, ->(drive_sync_id) { enqueued_drive_sync_ids << drive_sync_id }) do
      Observability::EventLogger.stub(:info, ->(event:, payload:) { events << { event: event, payload: payload } }) do
        result = Backups::ScheduleCaptureBackup.new(capture: capture, user: user).call

        assert result.scheduled?
        backup_record = result.backup_record
        drive_sync = capture.drive_syncs.order(created_at: :desc).first
        expected_folder_name = Drive::ExportLayout.record_folder_name(capture)

        assert_equal "Captures / #{expected_folder_name}", backup_record.remote_path
        assert_equal "manual", backup_record.metadata["requested_mode"]
        assert_equal "capture", backup_record.metadata["package_type"]
        assert_equal ["Captures", expected_folder_name], backup_record.metadata["folder_path"]
        assert drive_sync.mode_manual?
        assert_equal "manual", drive_sync.metadata["requested_mode"]
        assert_equal "capture", drive_sync.metadata["package_type"]
        assert_equal ["Captures", expected_folder_name], drive_sync.metadata["folder_path"]
        assert_equal [drive_sync.id], enqueued_drive_sync_ids
        assert_equal "drive.capture_backup.enqueued", events.last[:event]
        assert_equal "scheduled", events.last[:payload][:reason]
        assert_equal :manual, events.last[:payload][:mode]
      end
    end
  end

  test "supports automatic capture package scheduling" do
    user = build_user(email: "schedule-capture-backup-automatic@example.com")
    capture = build_capture(user: user, title: "Auto synced review")
    enqueued_drive_sync_ids = []

    Async::Dispatcher.stub(:enqueue_drive_export, ->(drive_sync_id) { enqueued_drive_sync_ids << drive_sync_id }) do
      result = Backups::ScheduleCaptureBackup.new(capture: capture, user: user, mode: :automatic).call

      assert result.scheduled?

      backup_record = result.backup_record
      drive_sync = capture.drive_syncs.order(created_at: :desc).first

      assert_equal "automatic", backup_record.metadata["requested_mode"]
      assert drive_sync.mode_automatic?
      assert_equal "automatic", drive_sync.metadata["requested_mode"]
      assert_equal [drive_sync.id], enqueued_drive_sync_ids
    end
  end

  test "reuses the existing backup record when rescheduling a capture package" do
    user = build_user(email: "schedule-capture-backup-reuse@example.com")
    capture = build_capture(user: user, title: "Reuse me")
    existing_backup_record = capture.backup_records.create!(
      user: user,
      provider: "google_drive",
      status: :uploaded,
      remote_path: "Captures / Old path",
      metadata: { "package_type" => "capture", "remote_folder_id" => "folder-123" }
    )
    enqueued_drive_sync_ids = []

    Async::Dispatcher.stub(:enqueue_drive_export, ->(drive_sync_id) { enqueued_drive_sync_ids << drive_sync_id }) do
      assert_no_difference -> { capture.backup_records.count } do
        assert_difference -> { capture.drive_syncs.count }, +1 do
          result = Backups::ScheduleCaptureBackup.new(capture: capture, user: user).call

          assert result.scheduled?
          assert_equal existing_backup_record.id, result.backup_record.id
          assert result.backup_record.reload.status_pending?
          assert_equal "manual", result.backup_record.metadata["requested_mode"]
          assert_equal "capture", result.backup_record.metadata["package_type"]
          assert_match(/\ACaptures \//, result.backup_record.remote_path)
        end
      end
    end

    drive_sync = capture.drive_syncs.order(created_at: :desc).first
    assert_equal [drive_sync.id], enqueued_drive_sync_ids
    assert_equal existing_backup_record.id, drive_sync.metadata["backup_record_id"]
  end

  test "returns the existing active backup instead of creating duplicates" do
    user = build_user(email: "schedule-capture-backup-pending@example.com")
    capture = build_capture(user: user, title: "Pending capture")
    backup_record = capture.backup_records.create!(
      user: user,
      provider: "google_drive",
      status: :pending,
      remote_path: "Captures / Pending capture",
      metadata: { "package_type" => "capture" }
    )
    drive_sync = capture.drive_syncs.create!(
      user: user,
      drive_folder_id: user.google_drive_folder_id,
      mode: :manual,
      status: :pending,
      metadata: { "backup_record_id" => backup_record.id, "package_type" => "capture" }
    )
    events = []

    Async::Dispatcher.stub(:enqueue_drive_export, ->(*) { flunk "should not enqueue duplicate capture backup" }) do
      Observability::EventLogger.stub(:info, ->(event:, payload:) { events << { event: event, payload: payload } }) do
        assert_no_difference -> { capture.backup_records.count } do
          assert_no_difference -> { capture.drive_syncs.count } do
            result = Backups::ScheduleCaptureBackup.new(capture: capture, user: user).call

            assert_not result.scheduled?
            assert_equal "already_pending", result.skip_reason
            assert_equal backup_record, result.backup_record
            assert_equal drive_sync, result.drive_sync
          end
        end
      end
    end

    assert_equal "drive.capture_backup.skipped", events.last[:event]
    assert_equal "already_pending", events.last[:payload][:reason]
    assert_equal backup_record.id, events.last[:payload][:backup_record_id]
    assert_equal drive_sync.id, events.last[:payload][:drive_sync_id]
  end

  test "returns a skipped result and logs when drive is not connected" do
    user = build_user(email: "schedule-capture-backup-skip@example.com", drive_ready: false)
    capture = build_capture(user: user, title: "No drive")
    events = []

    Observability::EventLogger.stub(:info, ->(event:, payload:) { events << { event: event, payload: payload } }) do
      result = Backups::ScheduleCaptureBackup.new(capture: capture, user: user).call

      assert_not result.scheduled?
      assert_equal "drive_not_connected", result.skip_reason
    end

    assert_equal "drive.capture_backup.skipped", events.last[:event]
    assert_equal "drive_not_connected", events.last[:payload][:reason]
    assert_empty capture.backup_records
    assert_empty capture.drive_syncs
  end
end
