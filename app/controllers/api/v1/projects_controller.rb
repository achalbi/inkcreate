module Api
  module V1
    class ProjectsController < BaseController
      def index
        render json: {
          projects: current_user.projects.active.recent_first.as_json(
            only: %i[id title description color slug archived_at created_at updated_at]
          )
        }
      end

      def show
        project = current_user.projects.find(params[:id])
        render json: { project: project.as_json(only: %i[id title description color slug archived_at created_at updated_at]) }
      end

      def create
        project = current_user.projects.create!(project_params)
        render json: { project: project.as_json(only: %i[id title description color slug archived_at created_at updated_at]) }, status: :created
      end

      def update
        project = current_user.projects.find(params[:id])
        project.update!(project_params)
        render json: { project: project.as_json(only: %i[id title description color slug archived_at created_at updated_at]) }
      end

      private

      def project_params
        params.require(:project).permit(:title, :description, :color)
      end
    end
  end
end
