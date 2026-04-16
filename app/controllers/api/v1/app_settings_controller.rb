module Api
  module V1
    class AppSettingsController < BaseController
      def show
        render json: { app_setting: current_user.ensure_app_setting!.as_json }
      end

      def update
        current_user.ensure_app_setting!.update!(app_setting_params)
        render json: { app_setting: current_user.ensure_app_setting!.as_json }
      end

      private

      def app_setting_params
        params.require(:app_setting).permit(:ocr_mode, :ai_enabled, :backup_enabled, :backup_provider, :capture_quality_preset)
      end
    end
  end
end
