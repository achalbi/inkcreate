require "json"
require "stringio"

module Drive
  class ExportRecord
    NOTES_FILE_NAME = "notes.txt".freeze
    MANIFEST_FILE_NAME = "manifest.json".freeze

    def initialize(google_drive_export:)
      @google_drive_export = google_drive_export
      @record = google_drive_export.exportable
      @user = google_drive_export.user
    end

    def call
      ensure_drive_ready!

      google_drive_export.update!(
        status: :running,
        last_attempted_at: Time.current,
        drive_folder_id: user.google_drive_folder_id,
        error_message: nil
      )

      relocate_remote_folder_if_structure_changed!

      folder_id = ensure_remote_folder!
      notes_file_id = upsert_text_file(
        file_id: google_drive_export.remote_notes_file_id,
        folder_id: folder_id,
        file_name: NOTES_FILE_NAME,
        content: notes_content,
        content_type: "text/plain"
      )
      manifest_file_id = upsert_text_file(
        file_id: google_drive_export.remote_manifest_file_id,
        folder_id: folder_id,
        file_name: MANIFEST_FILE_NAME,
        content: JSON.pretty_generate(manifest_payload),
        content_type: "application/json"
      )
      photo_file_ids = sync_photos(folder_id)

      google_drive_export.update!(
        status: :succeeded,
        remote_notes_file_id: notes_file_id,
        remote_manifest_file_id: manifest_file_id,
        remote_photo_file_ids: photo_file_ids,
        exported_at: Time.current,
        error_message: nil,
        metadata: export_metadata
      )
    rescue StandardError => error
      google_drive_export.update!(
        status: :failed,
        last_attempted_at: Time.current,
        error_message: error.message
      )
      raise
    end

    private

    attr_reader :google_drive_export, :record, :user

    def ensure_drive_ready!
      raise ArgumentError, "Google Drive backup is not configured" unless user.google_drive_ready?
      raise ArgumentError, "Record no longer exists" if record.blank?
    end

    def relocate_remote_folder_if_structure_changed!
      root_changed = google_drive_export.drive_folder_id.present? && google_drive_export.drive_folder_id != user.google_drive_folder_id
      path_changed = stored_folder_path_signature.present? && stored_folder_path_signature != current_folder_path_signature

      return unless root_changed || path_changed

      google_drive_export.update!(drive_folder_id: user.google_drive_folder_id)
      return reset_remote_references! if google_drive_export.remote_folder_id.blank?

      parent_folder_id = ensure_export_parent_folder_id
      remote_folder = drive_service.get_file(google_drive_export.remote_folder_id, fields: "id,name,parents")
      previous_parent_id = Array(remote_folder.parents).first
      update_options = { fields: "id" }
      if previous_parent_id.present? && previous_parent_id != parent_folder_id
        update_options[:add_parents] = parent_folder_id
        update_options[:remove_parents] = previous_parent_id
      end

      drive_service.update_file(
        remote_folder.id,
        Google::Apis::DriveV3::File.new(name: remote_folder_name),
        **update_options
      )

      google_drive_export.update!(
        metadata: google_drive_export.metadata.to_h.merge(
          "folder_path" => export_folder_segments,
          "folder_path_signature" => current_folder_path_signature
        )
      )
    rescue Google::Apis::ClientError
      reset_remote_references!
    end

    def ensure_remote_folder!
      return google_drive_export.remote_folder_id if google_drive_export.remote_folder_id.present?

      folder = Drive::EnsureFolderPath.new(
        user: user,
        parent_id: ensure_export_parent_folder_id,
        segments: [Drive::ExportLayout.record_folder_name(record)]
      ).call

      google_drive_export.update!(
        remote_folder_id: folder.id,
        metadata: google_drive_export.metadata.to_h.merge(
          "folder_path" => export_folder_segments,
          "folder_path_signature" => current_folder_path_signature
        )
      )
      folder.id
    end

    def ensure_export_parent_folder_id
      segments = Drive::ExportLayout.folder_segments(record)[0...-1]
      return user.google_drive_folder_id if segments.blank?

      Drive::EnsureFolderPath.new(
        user: user,
        parent_id: user.google_drive_folder_id,
        segments: segments
      ).call.id
    end

    def export_folder_segments
      Drive::ExportLayout.folder_segments(record)
    end

    def current_folder_path_signature
      Drive::ExportLayout.folder_path_signature(record)
    end

    def stored_folder_path_signature
      google_drive_export.metadata.to_h["folder_path_signature"].to_s.presence
    end

    def remote_folder_name
      Drive::ExportLayout.record_folder_name(record)
    end

    def notes_content
      [
        "Title: #{record_title}",
        metadata_lines,
        "",
        "Notes:",
        record.notes.presence || "(no notes)"
      ].flatten.join("\n")
    end

    def metadata_lines
      case record
      when Page
        [
          "Type: Notebook page",
          "Notebook: #{record.notebook.title}",
          "Chapter: #{record.chapter.title}",
          "Captured on: #{record.captured_on || "-"}",
          "Updated at: #{record.updated_at.iso8601}"
        ]
      when NotepadEntry
        [
          "Type: Daily page",
          "Entry date: #{record.entry_date}",
          "Updated at: #{record.updated_at.iso8601}"
        ]
      else
        []
      end
    end

    def export_metadata
      google_drive_export.metadata.to_h.merge(
        manifest_payload,
        "exported_at" => Time.current.iso8601,
        "folder_path" => export_folder_segments,
        "folder_path_signature" => current_folder_path_signature
      )
    end

    def manifest_payload
      payload = {
        "app" => "Inkcreate",
        "record_type" => record.class.name,
        "record_id" => record.id,
        "title" => record_title,
        "notes" => record.notes.to_s,
        "photo_count" => record.photos.attachments.size,
        "exported_photo_count" => exported_photo_count,
        "photos_exported" => photos_allowed_in_backups?,
        "updated_at" => record.updated_at.iso8601
      }

      case record
      when Page
        payload.merge!(
          "notebook_id" => record.notebook.id,
          "notebook_title" => record.notebook.title,
          "chapter_id" => record.chapter.id,
          "chapter_title" => record.chapter.title,
          "captured_on" => record.captured_on&.iso8601
        )
      when NotepadEntry
        payload.merge!(
          "entry_date" => record.entry_date&.iso8601
        )
      end

      payload
    end

    def sync_photos(folder_id)
      current_attachments = record.photos.attachments.index_by { |attachment| attachment.id.to_s }
      stored_mapping = google_drive_export.remote_photo_file_ids.to_h.stringify_keys

      unless photos_allowed_in_backups?
        stored_mapping.each_value { |file_id| delete_remote_file(file_id) }
        return {}
      end

      next_mapping = stored_mapping.slice(*current_attachments.keys)

      (stored_mapping.keys - current_attachments.keys).each do |removed_attachment_id|
        delete_remote_file(stored_mapping[removed_attachment_id])
      end

      current_attachments.each_with_index do |(attachment_id, attachment), index|
        next_mapping[attachment_id] = upsert_photo_file(
          file_id: stored_mapping[attachment_id],
          folder_id: folder_id,
          attachment: attachment,
          index: index + 1
        )
      end

      next_mapping
    end

    def photos_allowed_in_backups?
      user.ensure_app_setting!.include_photos_in_backups?
    end

    def exported_photo_count
      photos_allowed_in_backups? ? record.photos.attachments.size : 0
    end

    def upsert_text_file(file_id:, folder_id:, file_name:, content:, content_type:)
      metadata = Google::Apis::DriveV3::File.new(name: file_name, parents: [folder_id])
      io = StringIO.new(content)

      if file_id.present?
        drive_service.update_file(file_id, metadata, upload_source: io, content_type: content_type, fields: "id")
        file_id
      else
        drive_service.create_file(metadata, upload_source: io, content_type: content_type, fields: "id").id
      end
    rescue Google::Apis::ClientError
      drive_service.create_file(metadata, upload_source: StringIO.new(content), content_type: content_type, fields: "id").id
    end

    def upsert_photo_file(file_id:, folder_id:, attachment:, index:)
      metadata = Google::Apis::DriveV3::File.new(name: photo_file_name(attachment, index), parents: [folder_id])

      attachment.blob.open do |file|
        if file_id.present?
          drive_service.update_file(file_id, metadata, upload_source: file.path, content_type: attachment.blob.content_type, fields: "id")
          file_id
        else
          drive_service.create_file(metadata, upload_source: file.path, content_type: attachment.blob.content_type, fields: "id").id
        end
      end
    rescue Google::Apis::ClientError
      attachment.blob.open do |file|
        drive_service.create_file(metadata, upload_source: file.path, content_type: attachment.blob.content_type, fields: "id").id
      end
    end

    def delete_remote_file(file_id)
      return if file_id.blank?

      drive_service.delete_file(file_id)
    rescue Google::Apis::ClientError
      nil
    end

    def photo_file_name(attachment, index)
      extension = File.extname(attachment.blob.filename.to_s)
      base_name = File.basename(attachment.blob.filename.to_s, extension).parameterize.presence || "photo"
      format("photo-%<index>02d-%<name>s%<extension>s", index: index, name: base_name, extension: extension)
    end

    def record_title
      record.respond_to?(:display_title) ? record.display_title : record.title.to_s
    end

    def drive_service
      @drive_service ||= ClientFactory.build(user: user)
    end

    def reset_remote_references!
      google_drive_export.update!(
        drive_folder_id: user.google_drive_folder_id,
        remote_folder_id: nil,
        remote_notes_file_id: nil,
        remote_manifest_file_id: nil,
        remote_photo_file_ids: {},
        metadata: google_drive_export.metadata.to_h.merge(
          "folder_path" => export_folder_segments,
          "folder_path_signature" => current_folder_path_signature
        )
      )
    end
  end
end
