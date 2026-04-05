require "test_helper"

class RootRouteTest < ActionDispatch::IntegrationTest
  test "renders the landing page" do
    get root_url

    assert_response :success
    assert_includes response.body, "Inkcreate"
    assert_includes response.body, "Turn notebook pages into structured, searchable records."
    assert_includes response.body, "/api/v1/captures"
    assert_includes response.body, browser_sign_in_path
    assert_includes response.body, browser_sign_up_path
  end
end
