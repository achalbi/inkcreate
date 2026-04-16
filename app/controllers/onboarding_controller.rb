class OnboardingController < BrowserController
  before_action :require_authenticated_user!, only: :dismiss

  def show
    @signed_in = user_signed_in?
  end

  def dismiss
    current_user.update_column(:onboarding_completed_at, Time.current)
    head :no_content
  end
end
