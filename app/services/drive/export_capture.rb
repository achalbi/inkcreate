module Drive
  class ExportCapture
    def initialize(drive_sync:)
      @drive_sync = drive_sync
      @capture = drive_sync.capture
      @user = drive_sync.user
    end

    def call
      raise ArgumentError, "Photo backups are turned off in Privacy settings" unless user.ensure_app_setting!.include_photos_in_backups?

      drive_sync.update!(status: :running, last_attempted_at: Time.current)
      linked_backup_record&.update!(status: :running, last_attempt_at: Time.current)

      image_file = download_image
      text_body = capture.latest_ocr_result&.cleaned_text.to_s

      image_upload = drive_service.create_file(
        Google::Apis::DriveV3::File.new(
          name: capture_filename,
          parents: [drive_sync.drive_folder_id]
        ),
        upload_source: image_file.path,
        content_type: capture.content_type
      )

      text_upload = drive_service.create_file(
        Google::Apis::DriveV3::File.new(
          name: "#{capture.title.presence || File.basename(capture.original_filename, '.*')}.txt",
          parents: [drive_sync.drive_folder_id]
        ),
        upload_source: StringIO.new(text_body),
        content_type: "text/plain"
      )

      drive_sync.update!(
        status: :succeeded,
        image_file_id: image_upload.id,
        text_file_id: text_upload.id,
        exported_at: Time.current,
        error_message: nil
      )
      capture.update!(backup_status: :uploaded)
      linked_backup_record&.update!(
        status: :uploaded,
        remote_file_id: image_upload.id,
        remote_path: drive_sync.drive_folder_id,
        last_success_at: Time.current,
        error_message: nil
      )

      Observability::EventLogger.info(
        event: "drive.export.completed",
        payload: { capture_id: capture.id, drive_sync_id: drive_sync.id }
      )
    rescue StandardError => error
      drive_sync.update!(status: :failed, error_message: error.message, last_attempted_at: Time.current)
      capture.update!(backup_status: :failed)
      linked_backup_record&.update!(status: :failed, error_message: error.message, last_attempt_at: Time.current)
      Observability::EventLogger.info(
        event: "drive.export.failed",
        payload: { capture_id: capture.id, drive_sync_id: drive_sync.id, error: error.message }
      )
      raise
    ensure
      image_file&.close!
    end

    private

    attr_reader :drive_sync, :capture, :user

    def drive_service
      @drive_service ||= ClientFactory.build(user: user)
    end

    def download_image
      tempfile = Tempfile.new(["drive-export", File.extname(capture.storage_object_key)])
      storage.bucket(capture.storage_bucket).file(capture.storage_object_key).download(tempfile.path)
      tempfile
    end

    def storage
      @storage ||= Google::Cloud::Storage.new(project_id: ENV.fetch("GCP_PROJECT_ID"))
    end

    def capture_filename
      base = capture.title.presence || File.basename(capture.original_filename, ".*")
      "#{base}#{File.extname(capture.original_filename)}"
    end

    def linked_backup_record
      backup_record_id = drive_sync.metadata&.fetch("backup_record_id", nil)
      return if backup_record_id.blank?

      @linked_backup_record ||= capture.backup_records.find_by(id: backup_record_id)
    end
  end
end
