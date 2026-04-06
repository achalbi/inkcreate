module Settings
  class PrivacyController < BrowserController
    before_action :require_authenticated_user!

    def show
      redirect_to settings_path
    end

    def update
      current_user.ensure_app_setting!.update!(privacy_options: privacy_params.to_h)
      redirect_to settings_path, notice: "Privacy settings updated."
    end

    private

    def privacy_params
      params.require(:app_setting).permit(
        :allow_ocr_processing,
        :include_photos_in_backups,
        :keep_deleted_chapters_recoverable,
        :clear_backup_metadata_on_disconnect
      )
    end
  end
end
