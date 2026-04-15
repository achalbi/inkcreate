require "test_helper"
require "cgi"

class GoogleDriveOauthFlowTest < ActionDispatch::IntegrationTest
  StubDriveOauthClient = Struct.new(
    :token_payload,
    :authorization_calls,
    :exchange_calls,
    keyword_init: true
  ) do
    def authorization_url(state:)
      authorization_calls << { state: state }
      "https://accounts.google.com/o/oauth2/auth?state=#{CGI.escape(state)}"
    end

    def exchange_code!(code:)
      exchange_calls << { code: code }
      token_payload
    end
  end

  test "settings drive connect popup connects google drive and returns to settings" do
    user = build_user(email: "drive-popup@example.com")
    oauth_client = build_drive_oauth_client
    created_folder = Struct.new(:id, :name).new("folder-123", "Inkcreate")
    folder_creator = Object.new
    folder_creator.define_singleton_method(:call) { created_folder }

    Drive::OauthClient.stub(:configured?, true) do
      Drive::OauthClient.stub(:new, oauth_client) do
        Drive::CreateFolder.stub(:new, ->(**) { folder_creator }) do
          sign_in_browser_user(user)
          get settings_backup_path

          post settings_drive_connection_path, params: {
            authenticity_token: authenticity_token_for(settings_drive_connection_path),
            popup: true,
            return_to: settings_backup_path
          }

          assert_redirected_to(/accounts\.google\.com/)

          callback_state = oauth_state_from_redirect(response.redirect_url)

          get callback_api_v1_drive_connection_path, params: {
            code: "drive-oauth-code",
            state: callback_state
          }

          assert_response :success
          assert_includes response.body, "inkcreate:drive-oauth"
          assert_includes response.body, settings_backup_path

          get settings_backup_path

          assert_response :success
          assert_select ".badge", text: "Ready"
          assert_select ".ibox-content", text: /Connected/
          assert_select ".ibox-content", text: /folder-123/
        end
      end
    end

    user.reload

    assert user.google_drive_connected?
    assert_equal "folder-123", user.google_drive_folder_id
    assert_equal 1, oauth_client.authorization_calls.size
    assert_equal [{ code: "drive-oauth-code" }], oauth_client.exchange_calls
  end

  test "drive callback reconnects the user when session state is missing" do
    user = build_user(email: "drive-sessionless@example.com")
    oauth_client = build_drive_oauth_client
    created_folder = Struct.new(:id, :name).new("folder-456", "Inkcreate")
    folder_creator = Object.new
    folder_creator.define_singleton_method(:call) { created_folder }
    callback_state = Drive::OauthState.generate(
      user: user,
      return_to: settings_backup_path,
      popup: true
    )

    Drive::OauthClient.stub(:new, oauth_client) do
      Drive::CreateFolder.stub(:new, ->(**) { folder_creator }) do
        get callback_api_v1_drive_connection_path, params: {
          code: "drive-oauth-code",
          state: callback_state
        }

        assert_response :success
        assert_includes response.body, "inkcreate:drive-oauth"
        assert_includes response.body, settings_backup_path

        get settings_backup_path

        assert_response :success
        assert_select "h5", text: "Google Drive"
        assert_select ".badge", text: "Ready"
        assert_select ".ibox-content", text: /Connected/
        assert_select ".ibox-content", text: /folder-456/
      end
    end

    user.reload

    assert user.google_drive_connected?
    assert_equal "folder-456", user.google_drive_folder_id
    assert_equal [{ code: "drive-oauth-code" }], oauth_client.exchange_calls
  end

  private

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

  def build_drive_oauth_client
    StubDriveOauthClient.new(
      token_payload: {
        "access_token" => "drive-access-token",
        "refresh_token" => "drive-refresh-token",
        "expires_in" => 3600
      },
      authorization_calls: [],
      exchange_calls: []
    )
  end

  def oauth_state_from_redirect(redirect_url)
    uri = URI.parse(redirect_url)
    CGI.parse(uri.query.to_s).fetch("state").first
  end
end
