class OnboardingController < BrowserController
  def show
    @signed_in = user_signed_in?
  end
end
