module Drive
  class ScheduleRecordExport
    def initialize(record:)
      @record = record
      @user = record.user
    end

    def call
      return unless export_enabled?

      google_drive_export = GoogleDriveExport.find_or_initialize_by(exportable: record)
      google_drive_export.user ||= user
      google_drive_export.status = :pending
      google_drive_export.error_message = nil
      google_drive_export.remote_photo_file_ids ||= {}
      google_drive_export.save!

      Async::Dispatcher.enqueue_record_export(google_drive_export.id)
      google_drive_export
    end

    private

    attr_reader :record, :user

    def export_enabled?
      user.google_drive_ready? && user.ensure_app_setting!.google_drive_backup?
    end
  end
end
