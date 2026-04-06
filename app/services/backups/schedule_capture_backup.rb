module Backups
  class ScheduleCaptureBackup
    def initialize(capture:, user:)
      @capture = capture
      @user = user
    end

    def call
      raise ArgumentError, "Google Drive backup is not configured" unless user.google_drive_connected? && user.google_drive_folder_id.present?
      raise ArgumentError, "Photo backups are turned off in Privacy settings" unless user.ensure_app_setting!.include_photos_in_backups?

      backup_record = capture.backup_records.create!(
        user: user,
        provider: "google_drive",
        status: :pending,
        remote_path: user.google_drive_folder_id,
        metadata: { requested_at: Time.current.iso8601 }
      )

      drive_sync = capture.drive_syncs.create!(
        user: user,
        drive_folder_id: user.google_drive_folder_id,
        mode: :manual,
        status: :pending,
        metadata: { backup_record_id: backup_record.id }
      )

      capture.update!(backup_status: :pending)
      Async::Dispatcher.enqueue_drive_export(drive_sync.id)
      backup_record
    end

    private

    attr_reader :capture, :user
  end
end
