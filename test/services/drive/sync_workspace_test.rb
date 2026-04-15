require "test_helper"

class Drive::SyncWorkspaceTest < ActiveSupport::TestCase
  def build_user(email:, drive_ready: true, record_backups_enabled: true, media_backups_enabled: true)
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
      backup_enabled: record_backups_enabled,
      backup_provider: (record_backups_enabled ? "google_drive" : nil),
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

  test "returns a skip result when drive is not connected" do
    user = build_user(email: "workspace-sync-skip@example.com", drive_ready: false)

    result = Drive::SyncWorkspace.new(user: user).call

    assert_equal "drive_not_connected", result.skip_reason
    assert_equal 0, result.total_queued
  end

  test "queues record exports and capture backups while skipping fresh pending captures" do
    user = build_user(email: "workspace-sync-ready@example.com")
    queued_capture = build_capture(user: user, title: "Queued capture")
    pending_capture = build_capture(user: user, title: "Pending capture")
    pending_capture.drive_syncs.create!(
      user: user,
      drive_folder_id: user.google_drive_folder_id,
      mode: :manual,
      status: :pending,
      metadata: {}
    )
    pending_capture.backup_records.create!(
      user: user,
      provider: "google_drive",
      status: :pending
    )

    backfill_runner = Object.new
    backfill_runner.define_singleton_method(:call) { 4 }

    schedule_calls = []
    backup_runner = Object.new
    backup_runner.define_singleton_method(:call) do
      Backups::ScheduleCaptureBackup::Result.new(backup_record: BackupRecord.new, drive_sync: DriveSync.new)
    end

    Drive::BackfillRecordExports.stub :new, ->(**) {
      backfill_runner
    } do
      Backups::ScheduleCaptureBackup.stub :new, ->(capture:, user:, mode:) {
        schedule_calls << { capture_id: capture.id, user_id: user.id, mode: mode }
        backup_runner
      } do
        result = Drive::SyncWorkspace.new(user: user).call

        assert_nil result.skip_reason
        assert_equal 4, result.queued_record_exports
        assert_equal 1, result.queued_capture_backups
      end
    end

    assert_equal [{ capture_id: queued_capture.id, user_id: user.id, mode: :manual }], schedule_calls
  end

  test "does not queue an unchanged uploaded capture backup again" do
    user = build_user(email: "workspace-sync-no-duplicate-capture@example.com", record_backups_enabled: false, media_backups_enabled: true)
    capture = build_capture(user: user, title: "Already uploaded")
    capture.update!(backup_status: :uploaded)
    capture.backup_records.create!(
      user: user,
      provider: "google_drive",
      status: :uploaded,
      last_success_at: 5.minutes.from_now
    )

    Backups::ScheduleCaptureBackup.stub(:new, ->(*) { flunk "should not schedule unchanged uploaded capture" }) do
      result = Drive::SyncWorkspace.new(user: user).call

      assert_nil result.skip_reason
      assert_equal 0, result.queued_record_exports
      assert_equal 0, result.queued_capture_backups
    end
  end
end
