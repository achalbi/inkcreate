module Api
  module V1
    class CapturesController < BaseController
      def index
        captures = current_user.captures.includes(:page_template, :tags, :ocr_results).recent_first
        captures = captures.where(notebook_id: params[:notebook_id]) if params[:notebook_id].present?

        render json: { captures: captures.map { |capture| CaptureSerializer.new(capture).as_json } }
      end

      def show
        capture = current_user.captures.includes(:page_template, :tags, :ocr_results).find(params[:id])
        render json: { capture: CaptureSerializer.new(capture).as_json }
      end

      def create
        capture = Captures::CreateCapture.new(user: current_user, params: capture_params.to_h).call
        render json: { capture: CaptureSerializer.new(capture).as_json }, status: :created
      end

      def update
        capture = current_user.captures.find(params[:id])
        capture = Captures::UpdateMetadata.new(
          capture: capture,
          params: capture_update_params.to_h,
          user: current_user
        ).call
        render json: { capture: CaptureSerializer.new(capture.reload).as_json }
      end

      def reprocess
        capture = current_user.captures.find(params[:id])
        unless current_user.ensure_app_setting!.allow_ocr_processing?
          return render json: { error: "OCR is turned off in Privacy settings." }, status: :forbidden
        end

        ocr_job = Captures::RequestOcr.new(capture:, request_id: request.request_id).call

        render json: { capture_id: capture.id, ocr_job_id: ocr_job.id }, status: :accepted
      end

      def export_to_drive
        capture = current_user.captures.find(params[:id])
        unless current_user.ensure_app_setting!.include_photos_in_backups?
          return render json: { error: "Photo backups are turned off in Privacy settings." }, status: :forbidden
        end

        backup_record = Backups::ScheduleCaptureBackup.new(capture:, user: current_user).call

        render json: { backup_record_id: backup_record.id }, status: :accepted
      end

      def generate_summary
        capture = current_user.captures.find(params[:id])
        summary = Ai::SummarizeCapture.new(capture:, user: current_user).call

        render json: { ai_summary: summary.as_json }, status: :created
      end

      private

      def capture_params
        params.require(:capture).permit(
          :notebook_id,
          :project_id,
          :daily_log_id,
          :physical_page_id,
          :page_template_key,
          :page_type,
          :title,
          :description,
          :object_key,
          :original_filename,
          :captured_at,
          :meeting_label,
          :conference_label,
          :project_label,
          :drive_sync_mode,
          :client_draft_id,
          :save_destination,
          tags: [],
          metadata: {}
        )
      end

      def capture_update_params
        params.require(:capture).permit(
          :title,
          :description,
          :page_type,
          :favorite,
          :project_id,
          :daily_log_id,
          :physical_page_id,
          :meeting_label,
          :conference_label,
          :project_label,
          :page_template_id,
          tags: []
        )
      end

      def export_params
        ActionController::Parameters.new(params.fetch(:drive_sync, {})).permit(:drive_folder_id, :mode)
      end
    end
  end
end
