require "test_helper"
require "nokogiri"

class AdminNavigationTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(
      email: "admin@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :admin
    )
  end

  test "admin dashboard links resolve to admin pages" do
    sign_in_as(@admin)

    get admin_dashboard_path

    assert_response :success
    assert_select "a[href='#{admin_users_path}']"
    assert_select "a[href='#{admin_captures_path}']"
    assert_select "a[href='#{admin_operations_path}']"
    assert_select "a[href='#{dashboard_path}']"
    assert_select "a[href='#{root_path}']"

    get admin_captures_path
    assert_response :success
    assert_select "h1", /Review every notebook page moving through the system/

    get admin_operations_path
    assert_response :success
    assert_select "h1", /Watch OCR, sync, and backup queues before they become support issues/
  end

  private

  def sign_in_as(user)
    get browser_sign_in_path

    post browser_sign_in_path, params: {
      authenticity_token: authenticity_token_for(browser_sign_in_path),
      user: { email: user.email, password: "Password123!" }
    }

    assert_redirected_to admin_dashboard_path
  end

  def authenticity_token_for(action_path)
    document = Nokogiri::HTML.parse(response.body)
    form = document.css("form").find do |node|
      URI.parse(node["action"]).path == action_path
    end

    raise "No form found for #{action_path}" unless form

    form.at_css("input[name='authenticity_token']")["value"]
  end
end
