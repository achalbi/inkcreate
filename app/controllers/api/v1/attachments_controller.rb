module Api
  module V1
    class AttachmentsController < BaseController
      def index
        render json: {
          attachments: current_user.attachments.with_attached_asset.recent_first.map { |attachment| attachment_payload(attachment) }
        }
      end

      def create
        capture = current_user.captures.find(attachment_params.fetch(:capture_id))
        attachment = Attachments::CreateAttachment.new(
          user: current_user,
          capture: capture,
          params: attachment_params.except(:capture_id)
        ).call

        render json: { attachment: attachment_payload(attachment) }, status: :created
      end

      def destroy
        attachment = current_user.attachments.find(params[:id])
        attachment.asset.purge_later if attachment.asset.attached?
        attachment.destroy!
        head :no_content
      end

      private

      def attachment_params
        params.require(:attachment).permit(:capture_id, :attachment_type, :title, :url, :file)
      end

      def attachment_payload(attachment)
        {
          id: attachment.id,
          capture_id: attachment.capture_id,
          attachment_type: attachment.attachment_type,
          title: attachment.display_title,
          url: attachment.url,
          file_url: attachment.asset.attached? ? rails_blob_path(attachment.asset, only_path: true) : nil,
          content_type: attachment.content_type,
          byte_size: attachment.byte_size,
          created_at: attachment.created_at,
          updated_at: attachment.updated_at
        }
      end
    end
  end
end
