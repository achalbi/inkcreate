module Api
  module V1
    class SearchesController < BaseController
      def index
        captures = CaptureSearchQuery.new(
          user: current_user,
          query: params[:q],
          notebook_id: params[:notebook_id],
          page_template_key: params[:page_template_key],
          tag: params[:tag],
          project_id: params[:project_id],
          date: params[:date],
          page_type: params[:page_type]
        ).call

        render json: { captures: captures.map { |capture| CaptureSerializer.new(capture).as_json } }
      end
    end
  end
end
