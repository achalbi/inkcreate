class DailyLogsController < BrowserController
  before_action :require_authenticated_user!

  def index
    @today = Time.zone.today
    @daily_logs = current_user.daily_logs.recent_first.limit(21)
  end

  def show
    date = Date.iso8601(params[:date])
    @daily_log = current_user.daily_logs.find_or_create_by!(entry_date: date) do |daily_log|
      daily_log.title = date == Time.zone.today ? "Today" : date.strftime("%A")
    end
    @captures = @daily_log.captures.includes(:tags, :project).recent_first
    @tasks = @daily_log.tasks.recent_first
    @attachments = current_user.attachments.joins(:capture).where(captures: { daily_log_id: @daily_log.id }).recent_first.limit(16)
  end
end
