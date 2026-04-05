class CaptureStudioController < BrowserController
  before_action :require_authenticated_user!

  def show
    @projects = current_user.projects.active.order(:title)
    @today_log = current_user.daily_logs.find_or_create_by!(entry_date: Time.zone.today) do |daily_log|
      daily_log.title = "Today"
    end
    @page_templates = PageTemplate.order(:name)
    @physical_pages = current_user.physical_pages.active
    @recent_sync_jobs = current_user.sync_jobs.recent_first.limit(5)
  end
end
