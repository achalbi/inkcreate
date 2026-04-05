class TasksController < BrowserController
  before_action :require_authenticated_user!

  def index
    @task = current_user.tasks.new(priority: :medium)
    @tasks = current_user.tasks.includes(:project, :daily_log, :capture).recent_first
  end

  def create
    current_user.tasks.create!(task_params)
    redirect_to tasks_path, notice: "Task created."
  end

  def update
    task = current_user.tasks.find(params[:id])
    attrs = task_params.to_h
    if attrs.key?("completed") || attrs.key?(:completed)
      completed = ActiveModel::Type::Boolean.new.cast(attrs["completed"] || attrs[:completed])
      attrs[:completed] = completed
      attrs[:completed_at] = completed ? Time.current : nil
    end
    task.update!(attrs)
    redirect_back fallback_location: tasks_path, notice: "Task updated."
  end

  private

  def task_params
    params.fetch(:task, {}).permit(:title, :description, :priority, :due_date, :completed)
  end
end
