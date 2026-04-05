require "test_helper"

class BrowserAuthFlowTest < ActionDispatch::IntegrationTest
  test "first signup becomes admin and redirects to admin dashboard" do
    get browser_sign_up_path

    post browser_sign_up_path, params: {
      authenticity_token: authenticity_token_for(browser_sign_up_path),
      user: {
        email: "admin@example.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        time_zone: "UTC",
        locale: "en"
      }
    }

    user = User.find_by!(email: "admin@example.com")

    assert user.admin?
    assert_redirected_to admin_dashboard_path
  end

  test "subsequent signup becomes standard user and redirects to dashboard" do
    User.create!(
      email: "admin@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :admin
    )

    get browser_sign_up_path

    post browser_sign_up_path, params: {
      authenticity_token: authenticity_token_for(browser_sign_up_path),
      user: {
        email: "user@example.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        time_zone: "UTC",
        locale: "en"
      }
    }

    user = User.find_by!(email: "user@example.com")

    assert user.user?
    assert_redirected_to dashboard_path
  end

  test "admin can update another users role" do
    admin = User.create!(
      email: "admin@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :admin
    )
    user = User.create!(
      email: "user@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )

    get browser_sign_in_path
    post "/auth/sign-in", params: {
      authenticity_token: authenticity_token_for(browser_sign_in_path),
      user: { email: admin.email, password: "Password123!" }
    }

    assert_redirected_to admin_dashboard_path

    get admin_users_path
    post admin_user_role_path(user), params: {
      authenticity_token: authenticity_token_for(admin_user_role_path(user)),
      user: { role: "admin" }
    }

    assert_redirected_to admin_users_path
    assert user.reload.admin?
  end

  test "admin dashboard renders after sign in" do
    admin = User.create!(
      email: "admin@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :admin
    )

    get browser_sign_in_path
    post "/auth/sign-in", params: {
      authenticity_token: authenticity_token_for(browser_sign_in_path),
      user: { email: admin.email, password: "Password123!" }
    }

    follow_redirect!

    assert_response :success
    assert_select "h1", /Run the notebook pipeline with confidence/
    assert_select "a[href='#{admin_users_path}']", text: /Review users|Manage users|User roles/
  end
end
