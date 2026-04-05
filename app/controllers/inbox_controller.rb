class InboxController < BrowserController
  before_action :require_authenticated_user!

  def show
    @captures = current_user.captures.inbox.includes(:project, :daily_log, :tags).recent_first
  end
end
