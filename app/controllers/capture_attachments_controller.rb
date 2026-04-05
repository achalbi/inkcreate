class CaptureAttachmentsController < BrowserController
  before_action :require_authenticated_user!

  def create
    capture = current_user.captures.find(params[:capture_id])
    Attachments::CreateAttachment.new(
      user: current_user,
      capture: capture,
      params: attachment_params
    ).call
    redirect_to capture_path(capture), notice: "Attachment added."
  end

  private

  def attachment_params
    params.require(:attachment).permit(:attachment_type, :title, :url, :file)
  end
end
