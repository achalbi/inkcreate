module Settings
  class DriveConnectionsController < BrowserController
    before_action :require_authenticated_user!

    def create
      return redirect_to(settings_backup_path, alert: "Google Drive is not configured for this app yet.") unless Drive::OauthClient.configured?

      state = SecureRandom.hex(24)
      session[:drive_oauth_state] = state
      session[:drive_oauth_return_to] = settings_backup_path
      session[:drive_oauth_popup] = ActiveModel::Type::Boolean.new.cast(params[:popup])

      redirect_to Drive::OauthClient.new.authorization_url(state: state), allow_other_host: true
    end

    def update
      return redirect_to(settings_backup_path, alert: "Connect Google Drive before choosing a backup folder.") unless current_user.google_drive_connected?

      folder_id = Drive::FolderReference.extract(drive_connection_params[:folder_reference])
      return redirect_to(settings_backup_path, alert: "Enter a valid Google Drive folder link or folder ID.") if folder_id.blank?

      current_user.update!(google_drive_folder_id: folder_id)
      Drive::BackfillRecordExports.new(user: current_user).call
      redirect_to settings_backup_path, notice: "Google Drive folder updated."
    end

    def create_folder
      return redirect_to(settings_backup_path, alert: "Connect Google Drive before creating a backup folder.") unless current_user.google_drive_connected?

      folder = Drive::CreateFolder.new(user: current_user).call
      current_user.update!(google_drive_folder_id: folder.id)
      Drive::BackfillRecordExports.new(user: current_user).call

      redirect_to settings_backup_path, notice: "\"#{folder.name}\" is ready for backups."
    rescue StandardError => error
      redirect_to settings_backup_path, alert: error.message
    end

    def destroy
      had_backup_enabled = current_user.app_setting&.google_drive_backup?

      User.transaction do
        current_user.update!(
          google_drive_access_token: nil,
          google_drive_refresh_token: nil,
          google_drive_token_expires_at: nil,
          google_drive_connected_at: nil,
          google_drive_folder_id: nil
        )

        next unless had_backup_enabled

        current_user.ensure_app_setting!.update!(
          backup_enabled: false,
          backup_provider: nil
        )
      end

      notice = had_backup_enabled ? "Google Drive disconnected. Drive backups were turned off." : "Google Drive disconnected."
      redirect_to settings_backup_path, notice: notice
    end

    private

    def drive_connection_params
      params.require(:drive_connection).permit(:folder_reference)
    end
  end
end
