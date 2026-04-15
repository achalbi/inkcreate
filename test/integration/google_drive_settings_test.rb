require "test_helper"

class GoogleDriveSettingsTest < ActionDispatch::IntegrationTest
  def build_user(email:)
    User.create!(
      email: email,
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )
  end

  test "settings pages show google drive controls" do
    user = build_user(email: "drive-settings@example.com")
    entry = user.notepad_entries.create!(
      title: "Drive export source",
      notes: "Ready for export visibility.",
      entry_date: Date.current
    )
    user.google_drive_exports.create!(
      exportable: entry,
      status: :failed,
      error_message: "Drive folder missing",
      remote_photo_file_ids: {}
    )
    capture = user.captures.create!(
      title: "Quarterly kickoff",
      original_filename: "kickoff.jpg",
      content_type: "image/jpeg",
      byte_size: 1024,
      storage_bucket: "test-bucket",
      storage_object_key: "users/#{user.id}/uploads/test/kickoff.jpg",
      page_type: "blank"
    )
    user.backup_records.create!(
      capture: capture,
      provider: "google_drive",
      status: :uploaded,
      remote_path: "Captures / Quarterly kickoff (abcd1234)",
      metadata: { "package_type" => "capture" }
    )

    Drive::OauthClient.stub(:configured?, true) do
      sign_in_browser_user(user)
      get settings_path

      assert_response :success
      assert_select "h5", text: "Google Drive"
      assert_select "h5", text: "Record export history"
      assert_select ".ibox-content", text: /Drive export source/
      assert_select ".ibox-content", text: /Drive folder missing/
      assert_select ".ibox-content", text: /Capture package: Captures \/ Quarterly kickoff/
      assert_select ".workspace-inline-alert", text: /Capture backups export full capture packages/
      assert_select "form[action='#{settings_drive_connection_path}']"

      get settings_backup_path

      assert_response :success
      assert_select "h5", text: "Google Drive"
      assert_select "h5", text: "Backup behavior"
      assert_select ".ibox-content", text: /Capture package: Captures \/ Quarterly kickoff/
    end
  end

  test "user can save a drive folder from a shared link" do
    user = build_user(email: "drive-folder@example.com")
    user.update!(
      google_drive_refresh_token: "refresh-token",
      google_drive_connected_at: Time.current
    )

    sign_in_browser_user(user)
    get settings_backup_path

    patch settings_drive_connection_path, params: {
      authenticity_token: authenticity_token_for(settings_drive_connection_path),
      drive_connection: {
        folder_reference: "https://drive.google.com/drive/folders/1AbCdEfGhIjKlMnOpQr?usp=sharing"
      }
    }

    assert_redirected_to settings_backup_path
    assert_equal "1AbCdEfGhIjKlMnOpQr", user.reload.google_drive_folder_id
  end

  test "backup cannot be enabled before drive setup is complete" do
    user = build_user(email: "drive-guard@example.com")

    sign_in_browser_user(user)
    get settings_backup_path

    patch settings_backup_path, params: {
      authenticity_token: authenticity_token_for(settings_backup_path),
      app_setting: {
        backup_enabled: "true",
        backup_provider: "google_drive"
      }
    }

    assert_redirected_to settings_backup_path
    follow_redirect!

    assert_response :success
    assert_select ".alert", text: /Connect Google Drive before enabling Drive backups/
    assert_not user.reload.ensure_app_setting!.google_drive_backup?
  end

  test "enabling drive backup schedules one-time backfill only once" do
    user = build_user(email: "drive-backfill-once@example.com")
    user.update!(
      google_drive_refresh_token: "refresh-token",
      google_drive_connected_at: Time.current,
      google_drive_folder_id: "drive-folder-123"
    )
    backfill_calls = []

    Drive::BackfillRecordExports.stub :new, ->(user:) {
      runner = Object.new
      runner.define_singleton_method(:call) { backfill_calls << user.id }
      runner
    } do
      sign_in_browser_user(user)
      get settings_backup_path

      patch settings_backup_path, params: {
        authenticity_token: authenticity_token_for(settings_backup_path),
        app_setting: {
          backup_enabled: "true",
          backup_provider: "google_drive"
        }
      }

      assert_redirected_to settings_backup_path
      follow_redirect!
      assert_response :success

      get settings_backup_path
      assert_response :success

      patch settings_backup_path, params: {
        authenticity_token: authenticity_token_for(settings_backup_path),
        app_setting: {
          backup_enabled: "true",
          backup_provider: "google_drive"
        }
      }

      assert_redirected_to settings_backup_path
    end

    assert_equal [user.id], backfill_calls
  end
end
