class CaptureReferenceLinksController < BrowserController
  before_action :require_authenticated_user!

  def create
    capture = current_user.captures.find(params[:capture_id])
    current_user.reference_links.create!(
      source_capture: capture,
      target_capture: current_user.captures.find(reference_link_params.fetch(:target_capture_id)),
      relation_type: reference_link_params.fetch(:relation_type)
    )
    redirect_to capture_path(capture), notice: "Reference added."
  end

  private

  def reference_link_params
    params.require(:reference_link).permit(:target_capture_id, :relation_type)
  end
end
