module Admin
  class SettingsController < BaseController
    def show
      @global_setting = GlobalSetting.instance
    end

    def update
      @global_setting = GlobalSetting.instance
      @global_setting.update!(global_setting_params)
      redirect_to admin_settings_path, notice: "Settings updated."
    rescue ActiveRecord::RecordInvalid => e
      @global_setting = GlobalSetting.instance
      flash.now[:alert] = e.message
      render :show, status: :unprocessable_entity
    end

    private

    def global_setting_params
      params.require(:global_setting).permit(:password_auth_enabled)
    end
  end
end
