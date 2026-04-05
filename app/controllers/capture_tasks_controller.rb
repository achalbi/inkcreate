class CaptureTasksController < BrowserController
  before_action :require_authenticated_user!

  def create
    capture = current_user.captures.find(params[:capture_id])
    current_user.tasks.create!(
      task_params.merge(
        capture: capture,
        project: capture.project,
        daily_log: capture.daily_log
      )
    )
    redirect_to capture_path(capture), notice: "Task added."
  end

  private

  def task_params
    params.require(:task).permit(:title, :description, :priority, :due_date)
  end
end
