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

    Drive::OauthClient.stub(:configured?, true) do
      sign_in_browser_user(user)
      get settings_path

      assert_response :success
      assert_select "h5", text: "Google Drive"
      assert_select "form[action='#{settings_drive_connection_path}']"

      get settings_backup_path

      assert_response :success
      assert_select "h5", text: "Google Drive"
      assert_select "h5", text: "Backup behavior"
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
end
