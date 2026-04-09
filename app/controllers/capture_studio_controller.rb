class CaptureStudioController < BrowserController
  before_action :require_authenticated_user!

  def show
    @entry_date = Time.zone.today
  end
end
