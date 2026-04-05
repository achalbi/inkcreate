class LibraryController < BrowserController
  before_action :require_authenticated_user!

  def index
    @attachments = current_user.attachments.with_attached_asset.includes(:capture).recent_first
  end
end
