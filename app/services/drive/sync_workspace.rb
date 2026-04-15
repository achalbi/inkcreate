module Drive
  class SyncWorkspace
    RECENT_PENDING_WINDOW = 30.seconds

    Result = Struct.new(:queued_record_exports, :queued_capture_backups, :skip_reason, keyword_init: true) do
      def total_queued
        queued_record_exports.to_i + queued_capture_backups.to_i
      end
    end

    def initialize(user:)
      @user = user
    end

    def call
      if skip_reason.present?
        log(event: "drive.workspace_sync.skipped", reason: skip_reason)
        return Result.new(skip_reason: skip_reason, queued_record_exports: 0, queued_capture_backups: 0)
      end

      queued_record_exports = app_setting.google_drive_backup? ? BackfillRecordExports.new(user: user).call : 0
      queued_capture_backups = app_setting.include_media_in_backups? ? schedule_capture_backups : 0

      result = Result.new(
        queued_record_exports: queued_record_exports,
        queued_capture_backups: queued_capture_backups
      )

      log(
        event: "drive.workspace_sync.enqueued",
        reason: result.total_queued.positive? ? "scheduled" : "nothing_queued",
        queued_record_exports: result.queued_record_exports,
        queued_capture_backups: result.queued_capture_backups
      )

      result
    end

    def self.message_for(skip_reason)
      case skip_reason
      when "drive_not_connected"
        "Connect Google Drive before syncing."
      when "drive_folder_missing"
        "Choose a Google Drive folder before syncing."
      when "sync_disabled"
        "Enable Google Drive record backups or media backups before syncing."
      else
        "Google Drive sync could not be started right now."
      end
    end

    private

    attr_reader :user

    def app_setting
      @app_setting ||= user.ensure_app_setting!
    end

    def skip_reason
      return @skip_reason if defined?(@skip_reason)

      @skip_reason =
        if user.blank?
          "missing_user"
        elsif !user.google_drive_connected?
          "drive_not_connected"
        elsif user.google_drive_folder_id.blank?
          "drive_folder_missing"
        elsif !app_setting.google_drive_backup? && !app_setting.include_media_in_backups?
          "sync_disabled"
        end
    end

    def schedule_capture_backups
      scheduled = 0

      user.captures.find_each do |capture|
        next if recent_pending_capture_sync?(capture)
        next unless capture_needs_backup?(capture)

        result = Backups::ScheduleCaptureBackup.new(capture: capture, user: user, mode: :manual).call
        scheduled += 1 if result.scheduled?
      end

      scheduled
    end

    def recent_pending_capture_sync?(capture)
      capture.drive_syncs
        .where(status: DriveSync.statuses.fetch("pending"))
        .where("updated_at >= ?", RECENT_PENDING_WINDOW.ago)
        .exists? ||
        capture.backup_records
          .where(provider: "google_drive", status: BackupRecord.statuses.fetch("pending"))
          .where("updated_at >= ?", RECENT_PENDING_WINDOW.ago)
          .exists?
    end

    def capture_needs_backup?(capture)
      return true if capture.backup_status_local_only? || capture.backup_status_failed?

      latest_backup_record = capture.backup_records.where(provider: "google_drive").recent_first.first
      return true if latest_backup_record.blank?
      return true if latest_backup_record.status_failed?
      return true if latest_backup_record.last_success_at.blank?

      latest_backup_record.last_success_at < capture_last_change_at(capture)
    end

    def capture_last_change_at(capture)
      [
        capture.updated_at,
        capture.ocr_results.maximum(:updated_at),
        capture.ai_summaries.maximum(:updated_at),
        capture.attachments.maximum(:updated_at),
        capture.tasks.maximum(:updated_at),
        capture.capture_revisions.maximum(:updated_at),
        capture.outgoing_reference_links.maximum(:updated_at),
        capture.incoming_reference_links.maximum(:updated_at),
        capture.capture_tags.maximum(:updated_at)
      ].compact.max || capture.updated_at || Time.at(0)
    end

    def log(event:, reason:, queued_record_exports: 0, queued_capture_backups: 0)
      Observability::EventLogger.info(
        event: event,
        payload: {
          user_id: user&.id,
          reason: reason,
          drive_ready: user&.google_drive_ready? == true,
          record_backups_enabled: user&.ensure_app_setting!&.google_drive_backup? == true,
          media_backups_enabled: user&.ensure_app_setting!&.include_media_in_backups? == true,
          queued_record_exports: queued_record_exports,
          queued_capture_backups: queued_capture_backups
        }
      )
    end
  end
end
