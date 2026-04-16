require "test_helper"

class SettingsWorkspaceLauncherTest < ActionDispatch::IntegrationTest
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

  test "settings page shows workspace launcher controls" do
    user = build_user(email: "workspace-launcher-settings@example.com")

    sign_in_browser_user(user)
    get settings_path

    assert_response :success
    assert_select "h5", text: "Workspace launcher"
    assert_select "form[action='#{settings_workspace_launcher_path}']"
    assert_select "select[name='app_setting[enabled]']"
    assert_select "select[name='app_setting[idle_timeout_ms]'] option[value='60000'][selected='selected']", text: "1 minute"
  end

  test "user can update workspace launcher settings from settings" do
    user = build_user(email: "workspace-launcher-update@example.com")

    sign_in_browser_user(user)
    get settings_path

    patch settings_workspace_launcher_path, params: {
      authenticity_token: authenticity_token_for(settings_workspace_launcher_path),
      app_setting: {
        enabled: "false",
        idle_timeout_ms: "39600000"
      }
    }

    assert_redirected_to settings_path
    assert_not user.reload.ensure_app_setting!.workspace_launcher_enabled?
    assert_equal 39_600_000, user.ensure_app_setting!.workspace_launcher_idle_timeout_ms

    follow_redirect!

    assert_response :success
    assert_select ".flash-banner.notice .flash-banner__message", text: /Workspace launcher settings updated/
    assert_select "select[name='app_setting[enabled]'] option[value='false'][selected='selected']", text: "Off"
    assert_select "select[name='app_setting[idle_timeout_ms]'] option[value='39600000'][selected='selected']", text: "11 hours"
  end
end
