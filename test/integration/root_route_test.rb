require "test_helper"

class RootRouteTest < ActionDispatch::IntegrationTest
  test "renders the landing page" do
    get root_url

    assert_response :success
    assert_includes response.body, "Inkcreate"
    assert_includes response.body, "Turn notebook pages into structured, searchable records."
    assert_includes response.body, "Keep Inkcreate one tap away from your home screen."
    assert_includes response.body, "From photo to usable note in four deliberate steps."
    assert_includes response.body, browser_sign_in_path
    assert_includes response.body, browser_sign_up_path
    assert_select "[data-controller='install-prompt']", count: 1
    assert_select "button.ibox-toggle-button[data-action='install-prompt#toggleCollapse'][aria-expanded='true']"
    assert_select "button[data-action='install-prompt#prompt']", text: "Install app on mobile"
    assert_select "#page-loader"
    assert_select "link[href*='/inapp/page_loader.css?v=']"
    assert_select "script[src*='/scripts/page_loader.js?v=']"
  end
end
