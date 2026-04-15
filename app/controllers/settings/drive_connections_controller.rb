module Settings
  class DriveConnectionsController < BrowserController
    before_action :require_authenticated_user!

    def create
      return redirect_to(settings_path, alert: "Google Drive is not configured for this app yet.") unless Drive::OauthClient.configured?

      state = SecureRandom.hex(24)
      session[:drive_oauth_state] = state
      session[:drive_oauth_return_to] = settings_return_path
      session[:drive_oauth_popup] = ActiveModel::Type::Boolean.new.cast(params[:popup])

      redirect_to Drive::OauthClient.new.authorization_url(state: state), allow_other_host: true
    end

    def update
      return redirect_to(settings_return_path, alert: "Connect Google Drive before choosing a backup folder.") unless current_user.google_drive_connected?

      folder_id = Drive::FolderReference.extract(drive_connection_params[:folder_reference])
      return redirect_to(settings_return_path, alert: "Enter a valid Google Drive folder link or folder ID.") if folder_id.blank?

      current_user.update!(google_drive_folder_id: folder_id)
      Drive::BackfillRecordExports.new(user: current_user).call
      redirect_to settings_return_path, notice: "Google Drive folder updated."
    end

    def create_folder
      return redirect_to(settings_path, alert: "Connect Google Drive before creating a backup folder.") unless current_user.google_drive_connected?

      previous_folder_id = current_user.google_drive_folder_id
      folder = Drive::CreateFolder.new(user: current_user).call
      current_user.update!(google_drive_folder_id: folder.id)
      Drive::BackfillRecordExports.new(user: current_user).call

      notice =
        if previous_folder_id == folder.id
          "\"#{folder.name}\" is already selected for backups."
        else
          "\"#{folder.name}\" is ready for backups."
        end

      redirect_to settings_return_path, notice: notice
    rescue Drive::ClientFactory::AuthorizationRequiredError => error
      disconnect_google_drive_authorization!
      redirect_to settings_return_path, alert: error.message
    rescue StandardError => error
      redirect_to settings_return_path, alert: Drive::ErrorMessage.for(error)
    end

    def destroy
      app_setting = current_user.ensure_app_setting!
      had_backup_enabled = app_setting.google_drive_backup?
      purge_backup_metadata = app_setting.clear_backup_metadata_on_disconnect?
      backup_capture_ids = []

      User.transaction do
        if purge_backup_metadata
          backup_capture_ids = (
            current_user.backup_records.where(provider: "google_drive").distinct.pluck(:capture_id) +
            current_user.drive_syncs.distinct.pluck(:capture_id)
          ).uniq

          current_user.google_drive_exports.delete_all
          current_user.drive_syncs.delete_all
          current_user.backup_records.where(provider: "google_drive").delete_all
          current_user.captures.where(id: backup_capture_ids).update_all(
            backup_status: Capture.backup_statuses.fetch("local_only")
          )
        end

        current_user.update!(
          google_drive_access_token: nil,
          google_drive_refresh_token: nil,
          google_drive_token_expires_at: nil,
          google_drive_connected_at: nil,
          google_drive_folder_id: nil
        )

        next unless had_backup_enabled

        app_setting.update!(
          backup_enabled: false,
          backup_provider: nil
        )
      end

      notice =
        if had_backup_enabled && purge_backup_metadata
          "Google Drive disconnected. Drive backups were turned off and backup history was cleared."
        elsif had_backup_enabled
          "Google Drive disconnected. Drive backups were turned off."
        elsif purge_backup_metadata
          "Google Drive disconnected. Backup history was cleared."
        else
          "Google Drive disconnected."
        end

      redirect_to settings_return_path, notice: notice
    end

    private

    def disconnect_google_drive_authorization!
      current_user.update!(
        google_drive_access_token: nil,
        google_drive_refresh_token: nil,
        google_drive_token_expires_at: nil,
        google_drive_connected_at: nil
      )
    end

    def settings_return_path
      allowed_paths = [settings_path, settings_backup_path, settings_privacy_path]
      requested_path = params[:return_to].presence
      return requested_path if allowed_paths.include?(requested_path)

      referer_path = URI.parse(request.referer.to_s).path if request.referer.present?
      allowed_paths.find { |path| path == referer_path } || settings_backup_path
    rescue URI::InvalidURIError
      settings_backup_path
    end

    def drive_connection_params
      params.require(:drive_connection).permit(:folder_reference)
    end
  end
end
