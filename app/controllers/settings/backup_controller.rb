module Settings
  class BackupController < BrowserController
    before_action :require_authenticated_user!
    before_action :load_backup_settings

    def show
    end

    def sync
      result = Drive::SyncWorkspace.new(user: current_user).call

      if result.skip_reason.present?
        redirect_to sync_return_path, alert: Drive::SyncWorkspace.message_for(result.skip_reason)
      else
        redirect_to sync_return_path, notice: sync_notice_for(result)
      end
    rescue StandardError => error
      redirect_to sync_return_path, alert: Drive::ErrorMessage.for(error)
    end

    def update
      previously_enabled = @app_setting.google_drive_backup?

      if enabling_google_drive_backup? && !current_user.google_drive_connected?
        return redirect_to(settings_backup_path, alert: "Connect Google Drive before enabling Drive backups.")
      end

      if enabling_google_drive_backup? && current_user.google_drive_folder_id.blank?
        return redirect_to(settings_backup_path, alert: "Create or choose a Google Drive folder before enabling backups.")
      end

      current_user.ensure_app_setting!.update!(backup_params)
      schedule_backfill_if_needed(previously_enabled)
      redirect_to settings_backup_path, notice: "Backup settings updated."
    end

    private

    def load_backup_settings
      @app_setting = current_user.ensure_app_setting!
      @backup_records = current_user.backup_records.latest_per_capture_provider.recent_first.limit(20)
      @record_exports = current_user.google_drive_exports.includes(:exportable).recent_first.limit(20)
      @settings_user = current_user.dup
      @detected_time_zone_name = canonical_time_zone_name(browser_time_zone_name.presence)
      @selected_time_zone = @detected_time_zone_name || canonical_time_zone_name(current_user.time_zone)
      @settings_user.time_zone = @selected_time_zone if @selected_time_zone.present?
    end

    def backup_params
      params.require(:app_setting).permit(:backup_enabled, :backup_provider)
    end

    def enabling_google_drive_backup?
      attributes = backup_params

      ActiveModel::Type::Boolean.new.cast(attributes[:backup_enabled]) &&
        attributes[:backup_provider] == "google_drive"
    end

    def schedule_backfill_if_needed(previously_enabled)
      return unless enabling_google_drive_backup?
      return if previously_enabled

      Drive::BackfillRecordExports.new(user: current_user).call
    end

    def sync_notice_for(result)
      if result.total_queued.zero?
        return "Record backups are off. Enable backups in Settings." unless @app_setting.google_drive_backup?

        return "Google Drive sync checked current data. Nothing new was queued."
      end

      segments = []
      segments << helpers.pluralize(result.queued_record_exports, "record export") if result.queued_record_exports.to_i.positive?
      segments << helpers.pluralize(result.queued_capture_backups, "capture package") if result.queued_capture_backups.to_i.positive?

      "Queued Google Drive sync for #{segments.to_sentence}."
    end

    def sync_return_path
      safe_workspace_return_path(params[:return_to]) ||
        safe_workspace_return_path(referer_request_uri) ||
        settings_backup_path
    end

    def safe_workspace_return_path(candidate)
      return if candidate.blank?

      uri = URI.parse(candidate.to_s)
      return if uri.host.present? || uri.scheme.present?
      return if uri.path.blank? || !uri.path.start_with?("/")

      uri.query.present? ? "#{uri.path}?#{uri.query}" : uri.path
    rescue URI::InvalidURIError
      nil
    end

    def referer_request_uri
      return if request.referer.blank?

      URI.parse(request.referer).request_uri
    rescue URI::InvalidURIError
      nil
    end

    def canonical_time_zone_name(zone_name)
      return if zone_name.blank?

      ActiveSupport::TimeZone[zone_name]&.tzinfo&.name || zone_name.presence
    end
  end
end
