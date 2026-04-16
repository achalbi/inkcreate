require "test_helper"

class OnboardingFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      email: "onboarding@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )
  end

  test "dismiss marks onboarding as completed" do
    sign_in_browser_user(@user)
    get onboarding_path

    post onboarding_dismiss_path, params: {
      authenticity_token: authenticity_token_for(onboarding_dismiss_path)
    }

    assert_response :no_content
    assert @user.reload.onboarding_completed_at.present?
  end

  test "dismiss no-ops cleanly when the column is unavailable" do
    sign_in_browser_user(@user)
    get onboarding_path

    User.stub(:column_names, User.column_names - ["onboarding_completed_at"]) do
      post onboarding_dismiss_path, params: {
        authenticity_token: authenticity_token_for(onboarding_dismiss_path)
      }
    end

    assert_response :no_content
    assert_nil @user.reload.onboarding_completed_at
  end
end
