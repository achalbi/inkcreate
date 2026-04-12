class TaskSubtasksController < BrowserController
  before_action :require_authenticated_user!
  before_action :set_task_subtask, only: %i[update destroy]

  def create
    task = current_user.tasks.find(params[:task_id])
    position = task.task_subtasks.count
    subtask = task.task_subtasks.create!(
      title: params.dig(:task_subtask, :title).to_s.strip,
      position: position
    )

    respond_to do |format|
      format.html { redirect_to tasks_path }
      format.json { render json: { ok: true, id: subtask.id } }
    end
  end

  def update
    completed = ActiveModel::Type::Boolean.new.cast(params.dig(:task_subtask, :completed))
    attrs = { completed: completed }
    attrs[:completed_at] = completed ? Time.current : nil
    attrs[:title] = params.dig(:task_subtask, :title).to_s.strip if params.dig(:task_subtask, :title).present?

    @task_subtask.update!(attrs)

    respond_to do |format|
      format.html { redirect_to tasks_path }
      format.json { render json: { ok: true } }
    end
  end

  def destroy
    @task_subtask.destroy
    respond_to do |format|
      format.html { redirect_to tasks_path }
      format.json { render json: { ok: true } }
    end
  end

  private

  def set_task_subtask
    @task_subtask = current_user.tasks
                               .joins(:task_subtasks)
                               .find_by!(task_subtasks: { id: params[:id] })
                               .task_subtasks.find(params[:id])
  end
end
