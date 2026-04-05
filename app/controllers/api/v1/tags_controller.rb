module Api
  module V1
    class TagsController < BaseController
      def index
        render json: { tags: current_user.tags.order(:name).as_json(only: %i[id name color_token]) }
      end

      def create
        tag = current_user.tags.create!(tag_params)
        render json: { tag: tag.as_json(only: %i[id name color_token]) }, status: :created
      end

      def destroy
        current_user.tags.find(params[:id]).destroy!
        head :no_content
      end

      private

      def tag_params
        params.require(:tag).permit(:name, :color_token)
      end
    end
  end
end
