require "test_helper"

class CaptureBackupFlowTest < ActionDispatch::IntegrationTest
  def build_user(email:)
    user = User.create!(
      email: email,
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )
    user.update!(
      google_drive_connected_at: Time.current,
      google_drive_refresh_token: "refresh-token",
      google_drive_folder_id: "drive-root-folder"
    )
    user.ensure_app_setting!.update!(
      backup_enabled: true,
      backup_provider: "google_drive",
      privacy_options: user.ensure_app_setting!.privacy_options.merge("include_photos_in_backups" => true)
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

  test "browser capture backup schedules a pending backup record and drive sync" do
    user = build_user(email: "capture-backup-browser@example.com")
    capture = build_capture(user: user, title: "Sprint retro")
    enqueued_drive_sync_ids = []

    sign_in_browser_user(user)
    get capture_path(capture)

    Async::Dispatcher.stub(:enqueue_drive_export, ->(drive_sync_id) { enqueued_drive_sync_ids << drive_sync_id }) do
      assert_difference -> { capture.backup_records.count }, +1 do
        assert_difference -> { capture.drive_syncs.count }, +1 do
          post backup_capture_path(capture), params: {
            authenticity_token: authenticity_token_for(backup_capture_path(capture))
          }
        end
      end
    end

    assert_redirected_to capture_path(capture)
    assert_equal "Backup scheduled.", flash[:notice]

    backup_record = capture.backup_records.recent_first.first
    drive_sync = capture.drive_syncs.order(created_at: :desc).first
    expected_folder_name = Drive::ExportLayout.record_folder_name(capture)

    assert_equal "google_drive", backup_record.provider
    assert backup_record.status_pending?
    assert_equal "Captures / #{expected_folder_name}", backup_record.remote_path
    assert backup_record.metadata["requested_at"].present?
    assert_equal "capture", backup_record.metadata["package_type"]
    assert_equal ["Captures", expected_folder_name], backup_record.metadata["folder_path"]
    assert drive_sync.status_pending?
    assert_equal backup_record.id, drive_sync.metadata["backup_record_id"]
    assert_equal "capture", drive_sync.metadata["package_type"]
    assert_equal ["Captures", expected_folder_name], drive_sync.metadata["folder_path"]
    assert_equal [drive_sync.id], enqueued_drive_sync_ids
    assert capture.reload.backup_status_pending?
  end

  test "api capture export endpoint returns the scheduled backup record id" do
    user = build_user(email: "capture-backup-api@example.com")
    capture = build_capture(user: user, title: "Quarterly kickoff")
    enqueued_drive_sync_ids = []

    sign_in_browser_user(user)
    get capture_path(capture)

    Async::Dispatcher.stub(:enqueue_drive_export, ->(drive_sync_id) { enqueued_drive_sync_ids << drive_sync_id }) do
      assert_difference -> { capture.backup_records.count }, +1 do
        assert_difference -> { capture.drive_syncs.count }, +1 do
          post "/api/v1/captures/#{capture.id}/export_to_drive",
            params: {
              authenticity_token: authenticity_token_for("/api/v1/captures/#{capture.id}/export_to_drive")
            },
            headers: {
              "ACCEPT" => "application/json"
            }
        end
      end
    end

    assert_response :accepted

    payload = JSON.parse(response.body)
    backup_record = capture.backup_records.recent_first.first
    drive_sync = capture.drive_syncs.order(created_at: :desc).first

    assert_equal backup_record.id, payload["backup_record_id"]
    assert_equal [drive_sync.id], enqueued_drive_sync_ids
    assert_equal backup_record.id, drive_sync.metadata["backup_record_id"]
    assert capture.reload.backup_status_pending?
  end

  test "browser capture backup redirects with an alert when drive is not ready" do
    user = User.create!(
      email: "capture-backup-unready-browser@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )
    user.ensure_app_setting!.update!(
      backup_enabled: true,
      backup_provider: "google_drive",
      privacy_options: user.ensure_app_setting!.privacy_options.merge("include_photos_in_backups" => true)
    )
    capture = build_capture(user: user, title: "No drive yet")

    sign_in_browser_user(user)
    get capture_path(capture)

    assert_select "button[disabled]", text: "Backup to Drive"

    assert_no_difference -> { capture.backup_records.count } do
      assert_no_difference -> { capture.drive_syncs.count } do
        post backup_capture_path(capture), params: {
          authenticity_token: authenticity_token_for(backup_capture_path(capture))
        }
      end
    end

    assert_redirected_to capture_path(capture)
    assert_equal "Connect Google Drive before exporting a capture package.", flash[:alert]
    assert capture.reload.backup_status_local_only?
  end

  test "api capture export endpoint returns a validation error when drive is not ready" do
    user = User.create!(
      email: "capture-backup-unready-api@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )
    user.ensure_app_setting!.update!(
      backup_enabled: true,
      backup_provider: "google_drive",
      privacy_options: user.ensure_app_setting!.privacy_options.merge("include_photos_in_backups" => true)
    )
    capture = build_capture(user: user, title: "API no drive yet")

    sign_in_browser_user(user)
    get capture_path(capture)

    assert_no_difference -> { capture.backup_records.count } do
      assert_no_difference -> { capture.drive_syncs.count } do
        post "/api/v1/captures/#{capture.id}/export_to_drive",
          params: {
            authenticity_token: authenticity_token_for("/api/v1/captures/#{capture.id}/export_to_drive")
          },
          headers: {
            "ACCEPT" => "application/json"
          }
      end
    end

    assert_response :unprocessable_entity

    payload = JSON.parse(response.body)
    assert_equal "drive_not_connected", payload["reason"]
    assert_equal "Connect Google Drive before exporting a capture package.", payload["error"]
    assert capture.reload.backup_status_local_only?
  end
end
