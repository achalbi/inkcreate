class SearchController < BrowserController
  before_action :require_authenticated_user!

  def index
    @projects = current_user.projects.active.order(:title)
    @query = params[:q].to_s
    @captures = CaptureSearchQuery.new(
      user: current_user,
      query: @query,
      project_id: params[:project_id],
      date: params[:date],
      page_type: params[:page_type],
      tag: params[:tag]
    ).call.limit(30)
  end
end
