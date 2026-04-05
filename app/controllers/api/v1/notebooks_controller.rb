module Api
  module V1
    class NotebooksController < BaseController
      def index
        notebooks = current_user.notebooks.order(:title, :created_at)
        render json: { notebooks: notebooks.map { |notebook| NotebookSerializer.new(notebook).as_json } }
      end

      def show
        notebook = current_user.notebooks.find(params[:id])
        render json: { notebook: NotebookSerializer.new(notebook).as_json }
      end

      def create
        notebook = current_user.notebooks.create!(notebook_params)
        render json: { notebook: NotebookSerializer.new(notebook).as_json }, status: :created
      end

      def update
        notebook = current_user.notebooks.find(params[:id])
        notebook.update!(notebook_params)
        render json: { notebook: NotebookSerializer.new(notebook).as_json }
      end

      def destroy
        notebook = current_user.notebooks.find(params[:id])
        notebook.update!(archived_at: Time.current)
        head :no_content
      end

      private

      def notebook_params
        params.require(:notebook).permit(:title, :name, :description, :status, :slug, :color_token)
      end
    end
  end
end
