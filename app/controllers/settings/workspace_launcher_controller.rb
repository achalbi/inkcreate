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

      merged = app_setting.merged_launcher_preferences.merge(launcher_params.to_h.stringify_keys)
      app_setting.update!(launcher_preferences: merged)

      respond_to do |fmt|
        fmt.html { redirect_back fallback_location: settings_path, notice: "Workspace launcher settings updated." }
        fmt.json { render json: { ok: true, continue_scope: app_setting.workspace_launcher_continue_scope } }
      end
    end

    private

    def launcher_params
      params.require(:app_setting).permit(:enabled, :idle_timeout_ms, :continue_scope)
    end
  end
end
