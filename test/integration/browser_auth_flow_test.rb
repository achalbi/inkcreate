require "test_helper"

class BrowserAuthFlowTest < ActionDispatch::IntegrationTest
  StubGoogleOauthClient = Struct.new(
    :token_payload,
    :profile,
    :authorization_calls,
    :exchange_calls,
    :profile_calls,
    keyword_init: true
  ) do
    def authorization_url(state:, redirect_uri:)
      authorization_calls << { state: state, redirect_uri: redirect_uri }
      "https://accounts.google.com/o/oauth2/v2/auth?state=#{state}"
    end

    def exchange_code!(code:, redirect_uri:)
      exchange_calls << { code: code, redirect_uri: redirect_uri }
      token_payload
    end

    def fetch_profile!(access_token:)
      profile_calls << { access_token: access_token }
      profile
    end
  end

  test "first signup becomes admin and redirects to admin dashboard" do
    get browser_sign_up_path

    cookies[:browser_time_zone] = CGI.escape("Asia/Kolkata")

    post browser_sign_up_path, params: {
      authenticity_token: authenticity_token_for(browser_sign_up_path),
      user: {
        email: "admin@example.com",
        password: "Password123!",
        password_confirmation: "Password123!"
      }
    }

    user = User.find_by!(email: "admin@example.com")

    assert user.admin?
    assert_equal "Asia/Kolkata", user.time_zone
    assert_equal "en", user.locale
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
        password_confirmation: "Password123!"
      }
    }

    user = User.find_by!(email: "user@example.com")

    assert user.user?
    assert_equal "UTC", user.time_zone
    assert_equal "en", user.locale
    assert_redirected_to dashboard_path
  end

  test "signup form does not render time zone or locale fields" do
    get browser_sign_up_path

    assert_response :success
    assert_select "input[name='user[time_zone]']", count: 0
    assert_select "input[name='user[locale]']", count: 0
  end

  test "sign in and sign up pages show google auth buttons when configured" do
    with_singleton_override(Auth::GoogleOauthClient, :configured?, -> { true }) do
      get browser_sign_in_path

      assert_response :success
      assert_select "form[action='#{browser_google_auth_path}']"
      assert_select "button", text: /Continue with Google/

      get browser_sign_up_path

      assert_response :success
      assert_select "form[action='#{browser_google_auth_path}']"
      assert_select "button", text: /Continue with Google/
    end
  end

  test "google auth signs in an existing user" do
    user = User.create!(
      email: "google-existing@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )

    google_client = build_google_client(email: user.email)

    with_singleton_override(Auth::GoogleOauthClient, :configured?, -> { true }) do
      with_singleton_override(Auth::GoogleOauthClient, :new, -> { google_client }) do
        with_singleton_override(SecureRandom, :hex, ->(*) { "google-auth-state" }) do
          get browser_sign_in_path

          post browser_google_auth_path, params: {
            authenticity_token: authenticity_token_for(browser_google_auth_path)
          }

          assert_redirected_to "https://accounts.google.com/o/oauth2/v2/auth?state=google-auth-state"

          assert_no_changes -> { User.count } do
            get browser_google_auth_callback_path, params: {
              code: "google-auth-code",
              state: "google-auth-state"
            }
          end
        end
      end
    end

    assert_redirected_to dashboard_path
    assert_equal [{ state: "google-auth-state", redirect_uri: "http://www.example.com/auth/google/callback" }], google_client.authorization_calls
    assert_equal [{ code: "google-auth-code", redirect_uri: "http://www.example.com/auth/google/callback" }], google_client.exchange_calls
    assert_equal [{ access_token: "google-access-token" }], google_client.profile_calls
  end

  test "google auth creates a new user with the browser time zone" do
    google_client = build_google_client(email: "google-new@example.com")

    with_singleton_override(Auth::GoogleOauthClient, :configured?, -> { true }) do
      with_singleton_override(Auth::GoogleOauthClient, :new, -> { google_client }) do
        with_singleton_override(SecureRandom, :hex, ->(*) { "google-signup-state" }) do
          get browser_sign_up_path
          cookies[:browser_time_zone] = CGI.escape("Asia/Kolkata")

          post browser_google_auth_path, params: {
            authenticity_token: authenticity_token_for(browser_google_auth_path)
          }

          assert_redirected_to "https://accounts.google.com/o/oauth2/v2/auth?state=google-signup-state"

          assert_difference -> { User.count }, 1 do
            get browser_google_auth_callback_path, params: {
              code: "google-signup-code",
              state: "google-signup-state"
            }
          end
        end
      end
    end

    user = User.find_by!(email: "google-new@example.com")

    assert user.admin?
    assert_equal "Asia/Kolkata", user.time_zone
    assert_equal "en", user.locale
    assert_redirected_to admin_dashboard_path
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

  private

  def build_google_client(email:)
    StubGoogleOauthClient.new(
      token_payload: { "access_token" => "google-access-token" },
      profile: {
        "email" => email,
        "email_verified" => true
      },
      authorization_calls: [],
      exchange_calls: [],
      profile_calls: []
    )
  end

  def with_singleton_override(target, method_name, implementation)
    eigenclass = class << target; self; end
    backup_method = :"__codex_backup_#{method_name}_#{Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)}"
    had_original = eigenclass.method_defined?(method_name) || eigenclass.private_method_defined?(method_name)

    eigenclass.alias_method backup_method, method_name if had_original
    eigenclass.define_method(method_name, implementation)

    yield
  ensure
    eigenclass.remove_method(method_name) if eigenclass.method_defined?(method_name) || eigenclass.private_method_defined?(method_name)

    if had_original
      eigenclass.alias_method method_name, backup_method
      eigenclass.remove_method(backup_method)
    end
  end
end
