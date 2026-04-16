module Settings
  class CaptureQualityController < BrowserController
    before_action :require_authenticated_user!

    def show
      redirect_to settings_path
    end

    def update
      current_user.ensure_app_setting!.update!(capture_quality_params)
      redirect_to settings_path, notice: "Capture quality settings updated."
    end

    private

    def capture_quality_params
      params.require(:app_setting).permit(:capture_quality_preset)
    end
  end
end
