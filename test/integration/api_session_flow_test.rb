require "test_helper"

class ApiSessionFlowTest < ActionDispatch::IntegrationTest
  test "signed in api session can load notebooks" do
    user = User.create!(
      email: "api-user@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )
    user.notebooks.create!(name: "Field Notes", color_token: "forest")

    get "/api/v1/auth/csrf_token"

    assert_response :success
    assert_equal false, response.parsed_body.fetch("authenticated")

    post "/api/v1/auth/sign_in", params: {
      authenticity_token: response.parsed_body.fetch("csrf_token"),
      user: { email: user.email, password: "Password123!" }
    }

    assert_response :success
    assert_equal user.email, response.parsed_body.dig("user", "email")

    get "/api/v1/notebooks"

    assert_response :success
    assert_equal ["Field Notes"], response.parsed_body.fetch("notebooks").map { |notebook| notebook.fetch("name") }
  end
end
