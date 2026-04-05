module Api
  module V1
    class UploadUrlsController < BaseController
      def create
        issuer = Uploads::SignedUrlIssuer.new(
          user: current_user,
          filename: upload_params.fetch(:filename),
          content_type: upload_params.fetch(:content_type),
          byte_size: upload_params.fetch(:byte_size)
        )

        render json: issuer.call.as_json, status: :created
      end

      private

      def upload_params
        params.require(:upload).permit(:filename, :content_type, :byte_size)
      end
    end
  end
end
