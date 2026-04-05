module Settings
  class BackupController < BrowserController
    before_action :require_authenticated_user!

    def show
      @app_setting = current_user.ensure_app_setting!
      @backup_records = current_user.backup_records.recent_first.limit(20)
    end

    def update
      current_user.ensure_app_setting!.update!(backup_params)
      redirect_to settings_backup_path, notice: "Backup settings updated."
    end

    private

    def backup_params
      params.require(:app_setting).permit(:backup_enabled, :backup_provider)
    end
  end
end
