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

  test "api sign in treats malformed password hashes as invalid credentials" do
    user = User.create!(
      email: "api-invalid-hash@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )
    user.update_column(:encrypted_password, "not-a-bcrypt-hash")

    get "/api/v1/auth/csrf_token"

    post "/api/v1/auth/sign_in", params: {
      authenticity_token: response.parsed_body.fetch("csrf_token"),
      user: { email: user.email, password: "Password123!" }
    }

    assert_response :unauthorized
    assert_equal "Invalid email or password", response.parsed_body.fetch("error")
  end

  test "api sign in handles invalid hash raised directly during password verification" do
    user = User.create!(
      email: "api-raised-invalid-hash@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )

    User.stub(:find_for_authentication, ->(*) { user }) do
      user.stub(:valid_password?, ->(*) { raise BCrypt::Errors::InvalidHash }) do
        get "/api/v1/auth/csrf_token"

        post "/api/v1/auth/sign_in", params: {
          authenticity_token: response.parsed_body.fetch("csrf_token"),
          user: { email: user.email, password: "Password123!" }
        }
      end
    end

    assert_response :unauthorized
    assert_equal "Invalid email or password", response.parsed_body.fetch("error")
  end
end
