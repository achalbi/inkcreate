require "json"
require "stringio"

module Drive
  class ExportRecord
    NOTES_FILE_NAME = "notes.md".freeze
    MANIFEST_FILE_NAME = "manifest.json".freeze
    PHOTOS_FOLDER_NAME = "photos".freeze
    VOICE_NOTES_FOLDER_NAME = "voice_notes".freeze
    SCANNED_DOCUMENTS_FOLDER_NAME = "scanned_documents".freeze
    REMOTE_VOICE_NOTE_AUDIO_FILE_IDS_KEY = "remote_voice_note_audio_file_ids".freeze
    REMOTE_SCANNED_DOCUMENT_IMAGE_FILE_IDS_KEY = "remote_scanned_document_image_file_ids".freeze
    REMOTE_SCANNED_DOCUMENT_PDF_FILE_IDS_KEY = "remote_scanned_document_pdf_file_ids".freeze
    REMOTE_SCANNED_DOCUMENT_TEXT_FILE_IDS_KEY = "remote_scanned_document_text_file_ids".freeze

    def initialize(google_drive_export:)
      @google_drive_export = google_drive_export
      @record = google_drive_export.exportable
      @user = google_drive_export.user
    end

    def call
      ensure_drive_ready!

      requested_sections = prepare_export!

      relocate_remote_folder_if_structure_changed!

      folder_id = ensure_remote_folder!
      notes_file_id = should_update_notes_file?(requested_sections) ? upsert_text_file(
        file_id: google_drive_export.remote_notes_file_id,
        folder_id: folder_id,
        file_name: NOTES_FILE_NAME,
        content: notes_content,
        content_type: "text/markdown"
      ) : google_drive_export.remote_notes_file_id
      manifest_file_id = should_update_manifest_file?(requested_sections) ? upsert_text_file(
        file_id: google_drive_export.remote_manifest_file_id,
        folder_id: folder_id,
        file_name: MANIFEST_FILE_NAME,
        content: JSON.pretty_generate(manifest_payload),
        content_type: "application/json"
      ) : google_drive_export.remote_manifest_file_id
      photo_file_ids = should_sync_photos?(requested_sections) ? sync_photos(folder_id) : google_drive_export.remote_photo_file_ids.to_h
      voice_note_audio_file_ids = should_sync_voice_notes?(requested_sections) ? sync_voice_notes(folder_id) : export_metadata_hash(REMOTE_VOICE_NOTE_AUDIO_FILE_IDS_KEY)
      scanned_document_file_ids = should_sync_scanned_documents?(requested_sections) ? sync_scanned_documents(folder_id) : {
        images: export_metadata_hash(REMOTE_SCANNED_DOCUMENT_IMAGE_FILE_IDS_KEY),
        pdfs: export_metadata_hash(REMOTE_SCANNED_DOCUMENT_PDF_FILE_IDS_KEY),
        texts: export_metadata_hash(REMOTE_SCANNED_DOCUMENT_TEXT_FILE_IDS_KEY)
      }
      remaining_sections = pending_sections_after_processing(requested_sections)
      final_metadata = export_metadata.merge(
        REMOTE_VOICE_NOTE_AUDIO_FILE_IDS_KEY => voice_note_audio_file_ids,
        REMOTE_SCANNED_DOCUMENT_IMAGE_FILE_IDS_KEY => scanned_document_file_ids.fetch(:images),
        REMOTE_SCANNED_DOCUMENT_PDF_FILE_IDS_KEY => scanned_document_file_ids.fetch(:pdfs),
        REMOTE_SCANNED_DOCUMENT_TEXT_FILE_IDS_KEY => scanned_document_file_ids.fetch(:texts)
      )
      final_metadata[Drive::RecordExportSections::PENDING_METADATA_KEY] = remaining_sections if remaining_sections.any?

      google_drive_export.update!(
        status: :succeeded,
        remote_notes_file_id: notes_file_id,
        remote_manifest_file_id: manifest_file_id,
        remote_photo_file_ids: photo_file_ids,
        exported_at: Time.current,
        error_message: nil,
        metadata: final_metadata
      )
      enqueue_follow_up_export_if_needed!(remaining_sections)
    rescue StandardError => error
      restore_pending_sections!(requested_sections)
      google_drive_export.update!(
        status: :failed,
        last_attempted_at: Time.current,
        error_message: error.message
      )
      raise
    end

    private

    attr_reader :google_drive_export, :record, :user

    def prepare_export!
      requested_sections = effective_requested_sections
      google_drive_export.update!(
        status: :running,
        last_attempted_at: Time.current,
        drive_folder_id: user.google_drive_folder_id,
        error_message: nil
      )
      requested_sections
    end

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
      lines = [
        "# #{record_title}",
        "",
        *metadata_markdown_lines,
        "",
        "## Notes",
        "",
        record_notes_text.presence || "_(no notes)_"
      ]

      append_markdown_section(lines, "To-do list", todo_markdown_lines)
      append_markdown_section(lines, "Voice notes", voice_notes_markdown_lines)
      append_markdown_section(lines, "Scanned documents", scanned_documents_markdown_lines)

      lines.join("\n")
    end

    def metadata_markdown_lines
      metadata_lines.map { |line| "- #{line}" }
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
      google_drive_export.reload.metadata.to_h.except(
        Drive::RecordExportSections::PENDING_METADATA_KEY,
        REMOTE_VOICE_NOTE_AUDIO_FILE_IDS_KEY,
        REMOTE_SCANNED_DOCUMENT_IMAGE_FILE_IDS_KEY,
        REMOTE_SCANNED_DOCUMENT_PDF_FILE_IDS_KEY,
        REMOTE_SCANNED_DOCUMENT_TEXT_FILE_IDS_KEY
      ).merge(
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
        "notes" => record_notes_text,
        "photo_count" => record.photos.attachments.size,
        "exported_photo_count" => exported_photo_count,
        "photos_exported" => binary_assets_allowed_in_backups?,
        "voice_note_count" => record_voice_notes.size,
        "voice_note_audio_exported" => binary_assets_allowed_in_backups?,
        "voice_notes" => voice_notes_payload,
        "scanned_document_count" => record_scanned_documents.size,
        "scanned_document_files_exported" => binary_assets_allowed_in_backups?,
        "scanned_documents" => scanned_documents_payload,
        "todo_list" => todo_list_payload,
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

      unless binary_assets_allowed_in_backups?
        stored_mapping.each_value { |file_id| delete_remote_file(file_id) }
        return {}
      end

      next_mapping = stored_mapping.slice(*current_attachments.keys)
      photos_folder_id = current_attachments.any? ? ensure_asset_folder(folder_id, PHOTOS_FOLDER_NAME) : nil

      (stored_mapping.keys - current_attachments.keys).each do |removed_attachment_id|
        delete_remote_file(stored_mapping[removed_attachment_id])
      end

      current_attachments.each_with_index do |(attachment_id, attachment), index|
        next_mapping[attachment_id] = upsert_blob_file(
          file_id: stored_mapping[attachment_id],
          folder_id: photos_folder_id,
          blob: attachment.blob,
          file_name: photo_file_name(attachment, index + 1)
        )
      end

      next_mapping
    end

    def sync_voice_notes(folder_id)
      stored_mapping = export_metadata_hash(REMOTE_VOICE_NOTE_AUDIO_FILE_IDS_KEY)
      current_voice_notes = record_voice_notes.index_by { |voice_note| voice_note.id.to_s }

      (stored_mapping.keys - current_voice_notes.keys).each do |removed_voice_note_id|
        delete_remote_file(stored_mapping[removed_voice_note_id])
      end

      unless binary_assets_allowed_in_backups?
        stored_mapping.each_value { |file_id| delete_remote_file(file_id) }
        return {}
      end

      next_mapping = stored_mapping.slice(*current_voice_notes.keys)
      voice_notes_folder_id = ensure_asset_folder(folder_id, VOICE_NOTES_FOLDER_NAME)

      record_voice_notes.each_with_index do |voice_note, index|
        mapping_key = voice_note.id.to_s

        unless voice_note.audio.attached?
          delete_remote_file(stored_mapping[mapping_key])
          next_mapping.delete(mapping_key)
          next
        end

        next_mapping[mapping_key] = upsert_blob_file(
          file_id: stored_mapping[mapping_key],
          folder_id: voice_notes_folder_id,
          blob: voice_note.audio.blob,
          file_name: voice_note_file_name(voice_note, index + 1)
        )
      end

      next_mapping.compact
    end

    def sync_scanned_documents(folder_id)
      stored_image_mapping = export_metadata_hash(REMOTE_SCANNED_DOCUMENT_IMAGE_FILE_IDS_KEY)
      stored_pdf_mapping = export_metadata_hash(REMOTE_SCANNED_DOCUMENT_PDF_FILE_IDS_KEY)
      stored_text_mapping = export_metadata_hash(REMOTE_SCANNED_DOCUMENT_TEXT_FILE_IDS_KEY)
      current_documents = record_scanned_documents.index_by { |document| document.id.to_s }
      removed_document_ids = (stored_image_mapping.keys | stored_pdf_mapping.keys | stored_text_mapping.keys) - current_documents.keys

      removed_document_ids.each do |removed_document_id|
        delete_remote_file(stored_image_mapping[removed_document_id])
        delete_remote_file(stored_pdf_mapping[removed_document_id])
        delete_remote_file(stored_text_mapping[removed_document_id])
      end

      next_image_mapping = stored_image_mapping.slice(*current_documents.keys)
      next_pdf_mapping = stored_pdf_mapping.slice(*current_documents.keys)
      next_text_mapping = stored_text_mapping.slice(*current_documents.keys)
      scanned_documents_folder_id = current_documents.any? ? ensure_asset_folder(folder_id, SCANNED_DOCUMENTS_FOLDER_NAME) : nil

      record_scanned_documents.each_with_index do |document, index|
        mapping_key = document.id.to_s
        basename = scanned_document_file_basename(document, index + 1)

        if binary_assets_allowed_in_backups? && document.enhanced_image.attached?
          next_image_mapping[mapping_key] = upsert_blob_file(
            file_id: stored_image_mapping[mapping_key],
            folder_id: scanned_documents_folder_id,
            blob: document.enhanced_image.blob,
            file_name: "#{basename}-preview#{file_extension(document.enhanced_image.blob)}"
          )
        else
          delete_remote_file(stored_image_mapping[mapping_key])
          next_image_mapping.delete(mapping_key)
        end

        if binary_assets_allowed_in_backups? && document.document_pdf.attached?
          next_pdf_mapping[mapping_key] = upsert_blob_file(
            file_id: stored_pdf_mapping[mapping_key],
            folder_id: scanned_documents_folder_id,
            blob: document.document_pdf.blob,
            file_name: "#{basename}#{file_extension(document.document_pdf.blob)}"
          )
        else
          delete_remote_file(stored_pdf_mapping[mapping_key])
          next_pdf_mapping.delete(mapping_key)
        end

        if document.extracted_text.present?
          next_text_mapping[mapping_key] = upsert_text_file(
            file_id: stored_text_mapping[mapping_key],
            folder_id: scanned_documents_folder_id,
            file_name: "#{basename}-ocr.txt",
            content: document.extracted_text,
            content_type: "text/plain"
          )
        else
          delete_remote_file(stored_text_mapping[mapping_key])
          next_text_mapping.delete(mapping_key)
        end
      end

      {
        images: next_image_mapping.compact,
        pdfs: next_pdf_mapping.compact,
        texts: next_text_mapping.compact
      }
    end

    def binary_assets_allowed_in_backups?
      user.ensure_app_setting!.include_media_in_backups?
    end

    def exported_photo_count
      binary_assets_allowed_in_backups? ? record.photos.attachments.size : 0
    end

    def upsert_text_file(file_id:, folder_id:, file_name:, content:, content_type:)
      upsert_file(
        file_id: file_id,
        folder_id: folder_id,
        file_name: file_name,
        upload_source: StringIO.new(content),
        content_type: content_type
      )
    end

    def record_notes_text
      record.respond_to?(:plain_notes) ? record.plain_notes : record.notes.to_s
    end

    def upsert_blob_file(file_id:, folder_id:, blob:, file_name:)
      blob.open do |file|
        upsert_file(
          file_id: file_id,
          folder_id: folder_id,
          file_name: file_name,
          upload_source: file.path,
          content_type: blob.content_type
        )
      end
    end

    def upsert_file(file_id:, folder_id:, file_name:, upload_source:, content_type:)
      metadata = Google::Apis::DriveV3::File.new(name: file_name)

      if file_id.present?
        existing_file = drive_service.get_file(file_id, fields: "id,parents")
        update_options = {
          upload_source: upload_source,
          content_type: content_type,
          fields: "id"
        }
        existing_parent_id = Array(existing_file.parents).first
        if existing_parent_id != folder_id
          update_options[:add_parents] = folder_id
          update_options[:remove_parents] = existing_parent_id if existing_parent_id.present?
        end

        rewind_upload_source(upload_source)
        drive_service.update_file(file_id, metadata, **update_options)
        file_id
      else
        metadata.parents = [folder_id]
        rewind_upload_source(upload_source)
        drive_service.create_file(metadata, upload_source: upload_source, content_type: content_type, fields: "id").id
      end
    rescue Google::Apis::ClientError => error
      raise unless missing_remote_file?(error)

      metadata.parents = [folder_id]
      rewind_upload_source(upload_source)
      drive_service.create_file(metadata, upload_source: upload_source, content_type: content_type, fields: "id").id
    end

    def delete_remote_file(file_id)
      return if file_id.blank?

      drive_service.delete_file(file_id)
    rescue Google::Apis::ClientError
      nil
    end

    def rewind_upload_source(upload_source)
      upload_source.rewind if upload_source.respond_to?(:rewind)
    end

    def missing_remote_file?(error)
      error.respond_to?(:status_code) && error.status_code.to_i == 404 ||
        error.message.to_s.match?(/file not found|not\s+found/i)
    end

    def photo_file_name(attachment, index)
      extension = file_extension(attachment.blob)
      base_name = File.basename(attachment.blob.filename.to_s, extension).parameterize.presence || "photo"
      format("photo-%<index>02d-%<name>s%<extension>s", index: index, name: base_name, extension: extension)
    end

    def voice_note_file_name(voice_note, index)
      extension = file_extension(voice_note.audio.blob)
      timestamp = voice_note.recorded_at&.utc&.strftime("%Y%m%d-%H%M%S").presence || "recorded"

      format("voice-note-%<index>02d-%<timestamp>s%<extension>s", index: index, timestamp: timestamp, extension: extension)
    end

    def scanned_document_file_basename(document, index)
      base_name = document.title.to_s.parameterize.presence || "scan"
      format("scan-%<index>02d-%<name>s", index: index, name: base_name)
    end

    def file_extension(blob)
      File.extname(blob.filename.to_s).presence || ""
    end

    def ensure_asset_folder(folder_id, folder_name)
      Drive::EnsureFolderPath.new(
        user: user,
        parent_id: folder_id,
        segments: [folder_name]
      ).call.id
    end

    def export_metadata_hash(key)
      google_drive_export.metadata.to_h.fetch(key, {}).to_h.stringify_keys
    end

    def effective_requested_sections
      requested_sections = pending_requested_sections
      return Drive::RecordExportSections::ALL if full_export_required?(requested_sections)

      requested_sections
    end

    def pending_requested_sections
      Drive::RecordExportSections.normalize(
        google_drive_export.metadata.to_h[Drive::RecordExportSections::PENDING_METADATA_KEY]
      )
    end

    def full_export_required?(requested_sections)
      google_drive_export.remote_folder_id.blank? ||
        google_drive_export.remote_notes_file_id.blank? ||
        google_drive_export.remote_manifest_file_id.blank? ||
        requested_sections == Drive::RecordExportSections::ALL
    end

    def pending_sections_after_processing(processed_sections)
      current_pending_sections = Drive::RecordExportSections.normalize(
        google_drive_export.reload.metadata.to_h[Drive::RecordExportSections::PENDING_METADATA_KEY]
      )
      Drive::RecordExportSections.remaining(
        current: current_pending_sections,
        processed: processed_sections
      )
    end

    def enqueue_follow_up_export_if_needed!(remaining_sections)
      return if remaining_sections.blank?

      google_drive_export.update!(status: :pending, error_message: nil)
      Async::Dispatcher.enqueue_record_export(google_drive_export.id)
    end

    def restore_pending_sections!(requested_sections)
      metadata = google_drive_export.reload.metadata.to_h
      metadata[Drive::RecordExportSections::PENDING_METADATA_KEY] = Drive::RecordExportSections.normalize(
        metadata[Drive::RecordExportSections::PENDING_METADATA_KEY].to_a + Array(requested_sections)
      )
      google_drive_export.update_column(:metadata, metadata)
    rescue StandardError
      nil
    end

    def should_update_notes_file?(requested_sections)
      Drive::RecordExportSections.notes_required?(requested_sections)
    end

    def should_update_manifest_file?(requested_sections)
      Drive::RecordExportSections.manifest_required?(requested_sections)
    end

    def should_sync_photos?(requested_sections)
      Drive::RecordExportSections.photos_required?(requested_sections)
    end

    def should_sync_voice_notes?(requested_sections)
      Drive::RecordExportSections.voice_notes_required?(requested_sections)
    end

    def should_sync_scanned_documents?(requested_sections)
      Drive::RecordExportSections.scanned_documents_required?(requested_sections)
    end

    def record_voice_notes
      @record_voice_notes ||= if record.respond_to?(:voice_notes)
        record.voice_notes.includes(audio_attachment: :blob).reorder(recorded_at: :asc, created_at: :asc).to_a
      else
        []
      end
    end

    def record_scanned_documents
      @record_scanned_documents ||= if record.respond_to?(:scanned_documents)
        record.scanned_documents.includes(enhanced_image_attachment: :blob, document_pdf_attachment: :blob).order(created_at: :asc, id: :asc).to_a
      else
        []
      end
    end

    def record_todo_list
      @record_todo_list ||= record.respond_to?(:todo_list) ? record.todo_list : nil
    end

    def voice_notes_payload
      record_voice_notes.map do |voice_note|
        {
          "id" => voice_note.id,
          "recorded_at" => voice_note.recorded_at&.iso8601,
          "duration_seconds" => voice_note.duration_seconds,
          "byte_size" => voice_note.byte_size,
          "mime_type" => voice_note.mime_type,
          "filename" => voice_note.audio.attached? ? voice_note.audio.blob.filename.to_s : nil,
          "transcript" => voice_note.transcript.to_s.presence
        }
      end
    end

    def scanned_documents_payload
      record_scanned_documents.map do |document|
        {
          "id" => document.id,
          "title" => document.title,
          "created_at" => document.created_at.iso8601,
          "updated_at" => document.updated_at.iso8601,
          "enhancement_filter" => document.enhancement_filter,
          "ocr_engine" => document.ocr_engine,
          "ocr_language" => document.ocr_language,
          "ocr_confidence" => document.ocr_confidence,
          "tags" => document.tags_array,
          "has_preview_image" => document.enhanced_image.attached?,
          "has_pdf" => document.document_pdf.attached?,
          "extracted_text" => document.extracted_text.to_s.presence
        }
      end
    end

    def todo_list_payload
      todo_list = record_todo_list
      return nil if todo_list.blank?

      items = todo_list.todo_items.includes(:reminder).ordered.map do |item|
        {
          "id" => item.id,
          "content" => item.content,
          "position" => item.position,
          "completed" => item.completed,
          "completed_at" => item.completed_at&.iso8601,
          "reminder" => todo_item_reminder_payload(item)
        }
      end

      {
        "enabled" => todo_list.enabled,
        "hide_completed" => todo_list.hide_completed,
        "manually_reordered" => todo_list.has_attribute?(:manually_reordered) ? todo_list.manually_reordered : false,
        "completed_count" => todo_list.completed_count,
        "total_count" => todo_list.total_count,
        "items" => items
      }
    end

    def todo_item_reminder_payload(item)
      reminder = item.reminder
      return nil if reminder.blank?

      {
        "id" => reminder.id,
        "title" => reminder.title,
        "note" => reminder.note,
        "fire_at" => reminder.fire_at.iso8601,
        "status" => reminder.status
      }
    end

    def todo_markdown_lines
      todo_list = record_todo_list
      return [] if todo_list.blank?

      summary_line = "- Enabled: #{todo_list.enabled? ? "yes" : "no"}; hide completed: #{todo_list.hide_completed? ? "yes" : "no"}"
      item_lines = todo_list.todo_items.includes(:reminder).ordered.map do |item|
        line = "- [#{item.completed? ? "x" : " "}] #{item.content}"
        next line if item.reminder.blank?

        "#{line} (Reminder: #{item.reminder.title} at #{item.reminder.fire_at.iso8601})"
      end

      [summary_line, *(item_lines.presence || ["- _(no items)_"])]
    end

    def voice_notes_markdown_lines
      record_voice_notes.map do |voice_note|
        transcript_excerpt = voice_note.transcript.to_s.squish.truncate(140, separator: " ")
        line = "- #{voice_note.recorded_at&.in_time_zone(user.time_zone)&.strftime("%b %-d, %Y %H:%M") || "Recorded"} · #{voice_note.duration_seconds}s"
        transcript_excerpt.present? ? "#{line} · #{transcript_excerpt}" : line
      end
    end

    def scanned_documents_markdown_lines
      record_scanned_documents.map do |document|
        excerpt = document.extracted_text.to_s.squish.truncate(140, separator: " ")
        line = "- #{document.title.presence || "Untitled scan"}"
        excerpt.present? ? "#{line} · #{excerpt}" : line
      end
    end

    def append_markdown_section(lines, title, body_lines)
      return if body_lines.blank?

      lines << ""
      lines << "## #{title}"
      lines << ""
      lines.concat(body_lines)
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
          "folder_path_signature" => current_folder_path_signature,
          REMOTE_VOICE_NOTE_AUDIO_FILE_IDS_KEY => {},
          REMOTE_SCANNED_DOCUMENT_IMAGE_FILE_IDS_KEY => {},
          REMOTE_SCANNED_DOCUMENT_PDF_FILE_IDS_KEY => {},
          REMOTE_SCANNED_DOCUMENT_TEXT_FILE_IDS_KEY => {}
        )
      )
    end
  end
end
