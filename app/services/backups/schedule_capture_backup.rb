module Backups
  class ScheduleCaptureBackup
    Result = Struct.new(:backup_record, :drive_sync, :skip_reason, keyword_init: true) do
      def scheduled?
        backup_record.present? && drive_sync.present? && skip_reason.blank?
      end
    end

    def initialize(capture:, user:, mode: :manual)
      @capture = capture
      @user = user
      @mode = mode.to_sym
    end

    def call
      if skip_reason.present?
        log_skip(reason: skip_reason)
        return Result.new(skip_reason: skip_reason)
      end

      if active_drive_sync.present?
        log_skip(reason: "already_pending", backup_record: active_backup_record, drive_sync: active_drive_sync)
        return Result.new(
          backup_record: active_backup_record,
          drive_sync: active_drive_sync,
          skip_reason: "already_pending"
        )
      end

      backup_record = existing_backup_record || capture.backup_records.build
      backup_record.user ||= user
      backup_record.provider = "google_drive"
      backup_record.status = :pending
      backup_record.remote_path = planned_remote_path
      backup_record.error_message = nil
      backup_record.metadata = backup_record.metadata.to_h.merge(
        {
          requested_at: Time.current.iso8601,
          requested_mode: mode.to_s,
          package_type: "capture",
          folder_path: planned_folder_segments
        }
      )
      backup_record.save!

      drive_sync = capture.drive_syncs.create!(
        user: user,
        drive_folder_id: user.google_drive_folder_id,
        mode: mode,
        status: :pending,
        metadata: {
          backup_record_id: backup_record.id,
          requested_mode: mode.to_s,
          package_type: "capture",
          folder_path: planned_folder_segments
        }
      )

      capture.update!(backup_status: :pending)
      Async::Dispatcher.enqueue_drive_export(drive_sync.id)
      Observability::EventLogger.info(
        event: "drive.capture_backup.enqueued",
        payload: log_payload(backup_record: backup_record, drive_sync: drive_sync).merge(reason: "scheduled")
      )
      Result.new(backup_record: backup_record, drive_sync: drive_sync)
    end

    private

    attr_reader :capture, :user, :mode

    def skip_reason
      return @skip_reason if defined?(@skip_reason)

      @skip_reason =
        if user.blank?
          "missing_user"
        elsif !user.google_drive_connected?
          "drive_not_connected"
        elsif user.google_drive_folder_id.blank?
          "drive_folder_missing"
        elsif !user.ensure_app_setting!.include_media_in_backups?
          "media_backups_disabled"
        end
    end

    def planned_folder_segments
      [Drive::ExportCapture::CAPTURES_FOLDER_NAME, Drive::ExportLayout.record_folder_name(capture)]
    end

    def planned_remote_path
      planned_folder_segments.join(" / ")
    end

    def existing_backup_record
      @existing_backup_record ||= capture.backup_records
        .where(user: user, provider: "google_drive")
        .recent_first
        .first
    end

    def active_drive_sync
      @active_drive_sync ||= capture.drive_syncs
        .where(user: user, status: [DriveSync.statuses.fetch("pending"), DriveSync.statuses.fetch("running")])
        .order(updated_at: :desc, created_at: :desc)
        .first
    end

    def active_backup_record
      return @active_backup_record if defined?(@active_backup_record)

      backup_record_id = active_drive_sync&.metadata.to_h&.fetch("backup_record_id", nil)
      @active_backup_record =
        if backup_record_id.present?
          capture.backup_records.find_by(id: backup_record_id)
        else
          existing_backup_record
        end
    end

    def log_skip(reason:, backup_record: nil, drive_sync: nil)
      Observability::EventLogger.info(
        event: "drive.capture_backup.skipped",
        payload: log_payload(backup_record: backup_record, drive_sync: drive_sync).merge(reason: reason)
      )
    end

    def log_payload(backup_record: nil, drive_sync: nil)
      {
        capture_id: capture.id,
        user_id: user&.id,
        backup_record_id: backup_record&.id,
        drive_sync_id: drive_sync&.id,
        mode: mode,
        drive_ready: user&.google_drive_ready? == true,
        media_backups_enabled: user&.ensure_app_setting!&.include_media_in_backups? == true
      }
    end

    class << self
      def message_for(skip_reason)
        case skip_reason
        when "drive_not_connected"
          "Connect Google Drive before exporting a capture package."
        when "drive_folder_missing"
          "Choose a Google Drive folder before exporting a capture package."
        when "media_backups_disabled"
          "Media backups are turned off in Privacy settings."
        when "already_pending"
          "A Google Drive backup is already in progress."
        else
          "Capture backup could not be scheduled right now."
        end
      end
    end
  end
end
