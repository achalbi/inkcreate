require "test_helper"

class RootRouteTest < ActionDispatch::IntegrationTest
  test "renders the landing page" do
    get root_url

    assert_response :success
    assert_includes response.body, "Inkcreate"
    assert_includes response.body, "Turn notebook pages into digital records."
    assert_includes response.body, "Keep Inkcreate one tap away from your home screen."
    assert_includes response.body, "From page photo to searchable note in four steps."
    assert_includes response.body, browser_sign_in_path
    assert_includes response.body, browser_sign_up_path
    assert_select ".mobile-menu-toggle", count: 0
    assert_select ".topbar-right", count: 0
    assert_no_match "mobile-menu-open", response.body
    assert_select "[data-controller='install-prompt']", count: 2
    assert_select ".landing-top-cta .public-cta-section button[data-action='install-prompt#prompt'][hidden]", text: "Install on this device"
    assert_select "button.ibox-toggle-button[data-action='install-prompt#toggleCollapse'][aria-expanded='true']"
    assert_select "main button[data-action='install-prompt#prompt'][hidden]", text: "Install on this device"
    assert_select "#page-loader"
    assert_select "link[href*='/inapp/page_loader.css?v=']"
    assert_select "script[src*='/scripts/page_loader.js?v=']"
  end

  test "google-only mode routes landing CTAs to the common access page" do
    Auth::GoogleOauthClient.stub(:configured?, true) do
      GlobalSetting.instance.update!(password_auth_enabled: false)

      get root_url
    end

    assert_response :success
    assert_select ".mobile-menu-toggle", count: 0
    assert_select ".topbar-right", count: 0
    assert_no_match "mobile-menu-open", response.body
    assert_select "[data-controller='install-prompt']", count: 2
    assert_select "a[href='#{browser_sign_in_path}']", text: /Start with Google|Continue with Google/, minimum: 1
    assert_select ".public-cta-section .cta-section-actions a[href='#{browser_sign_in_path}']", text: "Continue with Google"
    assert_select ".landing-top-cta .public-cta-section button[data-action='install-prompt#prompt'][hidden]", text: "Install on this device"
    assert_no_match browser_sign_up_path, response.body
  end
end
