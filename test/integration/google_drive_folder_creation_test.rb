require "test_helper"

class GoogleDriveFolderCreationTest < ActionDispatch::IntegrationTest
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

  test "create folder asks the user to reconnect when drive authorization is no longer valid" do
    user = build_user(email: "drive-folder-create@example.com")
    user.update!(
      google_drive_access_token: "expired-access-token",
      google_drive_refresh_token: "refresh-token",
      google_drive_token_expires_at: 2.hours.ago,
      google_drive_connected_at: Time.current
    )

    reconnect_error = Drive::ClientFactory::AuthorizationRequiredError.new(
      "Google Drive authorization expired. Reconnect Google Drive and try again."
    )
    failing_creator = Object.new
    failing_creator.define_singleton_method(:call) { raise reconnect_error }

    Drive::OauthClient.stub(:configured?, true) do
      sign_in_browser_user(user)
      get settings_backup_path

      Drive::CreateFolder.stub(:new, ->(**) { failing_creator }) do
        post create_folder_settings_drive_connection_path, params: {
          authenticity_token: authenticity_token_for(create_folder_settings_drive_connection_path)
        }
      end

      assert_redirected_to settings_backup_path
      follow_redirect!

      assert_response :success
      assert_select ".flash-banner.alert .flash-banner__message", text: /Google Drive authorization expired/
    end

    user.reload

    assert_nil user.google_drive_access_token
    assert_nil user.google_drive_refresh_token
    assert_nil user.google_drive_token_expires_at
    assert_nil user.google_drive_connected_at
  end

  test "create folder shows a friendly message when the google drive api is disabled" do
    user = build_user(email: "drive-folder-api-disabled@example.com")
    user.update!(
      google_drive_access_token: "access-token",
      google_drive_refresh_token: "refresh-token",
      google_drive_token_expires_at: 1.hour.from_now,
      google_drive_connected_at: Time.current
    )

    api_disabled_error = StandardError.new(
      "PERMISSION_DENIED: Google Drive API has not been used in project 534102618638 before or it is disabled. Enable it by visiting https://console.developers.google.com/apis/api/drive.googleapis.com/overview?project=534102618638 then retry."
    )
    failing_creator = Object.new
    failing_creator.define_singleton_method(:call) { raise api_disabled_error }

    Drive::OauthClient.stub(:configured?, true) do
      sign_in_browser_user(user)
      get settings_backup_path

      Drive::CreateFolder.stub(:new, ->(**) { failing_creator }) do
        post create_folder_settings_drive_connection_path, params: {
          authenticity_token: authenticity_token_for(create_folder_settings_drive_connection_path)
        }
      end

      assert_redirected_to settings_backup_path
      follow_redirect!

      assert_response :success
      assert_select ".flash-banner.alert .flash-banner__message", text: /Google Drive API is not enabled for this deployment yet/
    end

    user.reload

    assert_equal "refresh-token", user.google_drive_refresh_token
    assert user.google_drive_connected?
  end
end
