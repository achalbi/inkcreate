require "test_helper"

class SettingsCaptureQualityTest < ActionDispatch::IntegrationTest
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

  test "settings page shows capture quality controls" do
    user = build_user(email: "capture-quality-settings@example.com")

    sign_in_browser_user(user)
    get settings_path

    assert_response :success
    assert_select "h5", text: "Capture quality"
    assert_select "form[action='#{settings_capture_quality_path}']"
    assert_includes response.body, 'data-capture-quality-preset="optimized"'
    assert_select "input[type=radio][name='app_setting[capture_quality_preset]'][value='optimized'][checked='checked']"
  end

  test "user can update capture quality preset from settings" do
    user = build_user(email: "capture-quality-update@example.com")

    sign_in_browser_user(user)
    get settings_path

    patch settings_capture_quality_path, params: {
      authenticity_token: authenticity_token_for(settings_capture_quality_path),
      app_setting: { capture_quality_preset: "high" }
    }

    assert_redirected_to settings_path
    assert_equal "high", user.reload.ensure_app_setting!.capture_quality_preset

    follow_redirect!

    assert_response :success
    assert_select ".flash-banner.notice .flash-banner__message", text: /Capture quality settings updated/
    assert_includes response.body, 'data-capture-quality-preset="high"'
    assert_select "input[type=radio][name='app_setting[capture_quality_preset]'][value='high'][checked='checked']"
  end
end
