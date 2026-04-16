module Drive
  class ScheduleRecordExport
    def initialize(record:, sections: nil)
      @record = record
      @user = record.user
      @sections = Drive::RecordExportSections.normalize(sections)
    end

    def call
      if skip_reason.present?
        log_skip(reason: skip_reason)
        return
      end

      google_drive_export = GoogleDriveExport.find_or_initialize_by(exportable: record)
      google_drive_export.user ||= user
      google_drive_export.remote_photo_file_ids ||= {}
      merge_pending_sections!(google_drive_export)
      if active_export?(google_drive_export)
        google_drive_export.save! if google_drive_export.changed?
        log_skip(reason: "already_pending", google_drive_export: google_drive_export)
        return nil
      end

      google_drive_export.status = :pending
      google_drive_export.error_message = nil
      google_drive_export.save!

      Async::Dispatcher.enqueue_record_export(google_drive_export.id)
      Observability::EventLogger.info(
        event: "drive.record_export.enqueued",
        payload: log_payload(google_drive_export).merge(reason: "scheduled")
      )
      google_drive_export
    end

    private

    attr_reader :record, :user, :sections

    def skip_reason
      return @skip_reason if defined?(@skip_reason)

      @skip_reason =
        if user.blank?
          "missing_user"
        elsif !user.google_drive_connected?
          "drive_not_connected"
        elsif user.google_drive_folder_id.blank?
          "drive_folder_missing"
        elsif !user.ensure_app_setting!.google_drive_backup?
          "backup_disabled"
        end
    end

    def active_export?(google_drive_export)
      google_drive_export.persisted? &&
        (google_drive_export.status_pending? || google_drive_export.status_running?)
    end

    def merge_pending_sections!(google_drive_export)
      metadata = google_drive_export.metadata.to_h
      metadata[Drive::RecordExportSections::PENDING_METADATA_KEY] = Drive::RecordExportSections.normalize(
        metadata[Drive::RecordExportSections::PENDING_METADATA_KEY].to_a + sections
      )
      google_drive_export.metadata = metadata
    end

    def log_skip(reason:, google_drive_export: nil)
      Observability::EventLogger.info(
        event: "drive.record_export.skipped",
        payload: log_payload(google_drive_export).merge(reason: reason)
      )
    end

    def log_payload(google_drive_export = nil)
      {
        record_type: record.class.name,
        record_id: record.id,
        export_id: google_drive_export&.id,
        drive_ready: user&.google_drive_ready? == true
      }
    end
  end
end
