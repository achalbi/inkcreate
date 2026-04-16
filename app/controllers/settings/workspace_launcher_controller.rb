module Settings
  class WorkspaceLauncherController < BrowserController
    before_action :require_authenticated_user!

    def show
      redirect_to settings_path
    end

    def update
      app_setting = current_user.ensure_app_setting!
      unless app_setting.launcher_preferences_supported?
        return redirect_to settings_path, alert: "Workspace launcher settings will appear after the latest app migration is loaded."
      end

      app_setting.update!(launcher_preferences: launcher_params.to_h)
      redirect_to settings_path, notice: "Workspace launcher settings updated."
    end

    private

    def launcher_params
      params.require(:app_setting).permit(:enabled, :idle_timeout_ms)
    end
  end
end
