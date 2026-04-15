class CapturesController < BrowserController
  before_action :require_authenticated_user!
  before_action :set_capture

  def show
    @projects = current_user.projects.active.order(:title)
    @daily_logs = current_user.daily_logs.recent_first.limit(14)
    @physical_pages = current_user.physical_pages.active
    @related_capture_options = current_user.captures.where.not(id: @capture.id).recent_first.limit(20)
  end

  def update
    Captures::UpdateMetadata.new(capture: @capture, params: capture_params.to_h, user: current_user).call
    redirect_to capture_path(@capture), notice: "Capture updated."
  end

  def extract_text
    return redirect_to(capture_path(@capture), alert: "OCR is turned off in Privacy settings.") unless current_user.ensure_app_setting!.allow_ocr_processing?

    Captures::RequestOcr.new(capture: @capture, request_id: request.request_id).call
    redirect_to capture_path(@capture), notice: "Text extraction started."
  end

  def generate_summary
    Ai::SummarizeCapture.new(capture: @capture, user: current_user).call
    redirect_to capture_path(@capture), notice: "Summary generated."
  end

  def backup
    result = Backups::ScheduleCaptureBackup.new(capture: @capture, user: current_user).call
    if result.scheduled?
      redirect_to capture_path(@capture), notice: "Backup scheduled."
    else
      redirect_to capture_path(@capture), alert: Backups::ScheduleCaptureBackup.message_for(result.skip_reason)
    end
  end

  def preview
    redirect_to Captures::PreviewUrl.new(capture: @capture).call, allow_other_host: true
  end

  private

  def set_capture
    @capture = current_user.captures.includes(
      :project,
      :daily_log,
      :physical_page,
      :page_template,
      :tags,
      { attachments: [asset_attachment: :blob] },
      :ai_summaries,
      :capture_revisions,
      outgoing_reference_links: :target_capture
    ).find(params[:id])
  end

  def capture_params
    params.require(:capture).permit(:title, :description, :page_type, :favorite, :project_id, :daily_log_id, :physical_page_id, tags: [])
  end
end
