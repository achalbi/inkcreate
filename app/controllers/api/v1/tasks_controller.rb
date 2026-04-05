module Api
  module V1
    class TasksController < BaseController
      def index
        render json: {
          tasks: current_user.tasks.recent_first.as_json(
            only: %i[id title description completed priority due_date capture_id project_id daily_log_id created_at updated_at]
          )
        }
      end

      def create
        task = current_user.tasks.create!(task_params)
        render json: { task: task.as_json(only: %i[id title description completed priority due_date capture_id project_id daily_log_id created_at updated_at]) }, status: :created
      end

      def update
        task = current_user.tasks.find(params[:id])
        task.update!(task_params)
        render json: { task: task.as_json(only: %i[id title description completed priority due_date capture_id project_id daily_log_id created_at updated_at]) }
      end

      private

      def task_params
        params.require(:task).permit(:title, :description, :completed, :priority, :due_date, :capture_id, :project_id, :daily_log_id)
      end
    end
  end
end
