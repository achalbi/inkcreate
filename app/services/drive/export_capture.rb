require "json"
require "stringio"

module Drive
  class ExportCapture
    PACKAGE_VERSION = 1
    CAPTURES_FOLDER_NAME = "Captures".freeze
    MANIFEST_FILE_NAME = "manifest.json".freeze
    LATEST_OCR_FILE_NAME = "latest-ocr.txt".freeze
    ATTACHMENTS_FOLDER_NAME = "attachments".freeze
    REMOTE_FOLDER_ID_KEY = "remote_folder_id".freeze
    REMOTE_MANIFEST_FILE_ID_KEY = "remote_manifest_file_id".freeze
    REMOTE_ATTACHMENT_FILE_IDS_KEY = "remote_attachment_file_ids".freeze

    def initialize(drive_sync:)
      @drive_sync = drive_sync
      @capture = drive_sync.capture
      @user = drive_sync.user
    end

    def call
      ensure_drive_ready!

      drive_sync.update!(
        status: :running,
        last_attempted_at: Time.current,
        drive_folder_id: user.google_drive_folder_id,
        error_message: nil
      )
      linked_backup_record&.update!(status: :running, last_attempt_at: Time.current)

      relocate_remote_folder_if_structure_changed!

      folder_id = ensure_remote_folder!
      image_file = download_image
      image_file_id = upsert_capture_image(folder_id:, image_file:)
      latest_ocr_file_id = sync_latest_ocr_text(folder_id)
      manifest_file_id = upsert_text_file(
        file_id: effective_manifest_file_id,
        folder_id: folder_id,
        file_name: MANIFEST_FILE_NAME,
        content: JSON.pretty_generate(manifest_payload),
        content_type: "application/json"
      )
      attachment_file_ids = sync_uploaded_attachments(folder_id)

      drive_sync.update!(
        status: :succeeded,
        image_file_id: image_file_id,
        text_file_id: latest_ocr_file_id,
        exported_at: Time.current,
        error_message: nil,
        metadata: export_metadata.merge(
          REMOTE_FOLDER_ID_KEY => folder_id,
          REMOTE_MANIFEST_FILE_ID_KEY => manifest_file_id,
          REMOTE_ATTACHMENT_FILE_IDS_KEY => attachment_file_ids
        )
      )
      capture.update!(backup_status: :uploaded)
      linked_backup_record&.update!(
        status: :uploaded,
        remote_file_id: folder_id,
        remote_path: current_folder_path_display,
        last_success_at: Time.current,
        error_message: nil,
        metadata: backup_record_metadata.merge(
          REMOTE_FOLDER_ID_KEY => folder_id,
          "remote_image_file_id" => image_file_id,
          "remote_latest_ocr_file_id" => latest_ocr_file_id,
          "remote_manifest_file_id" => manifest_file_id,
          REMOTE_ATTACHMENT_FILE_IDS_KEY => attachment_file_ids
        )
      )

      Observability::EventLogger.info(
        event: "drive.export.completed",
        payload: { capture_id: capture.id, drive_sync_id: drive_sync.id, remote_folder_id: folder_id }
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

    def ensure_drive_ready!
      raise ArgumentError, "Google Drive backup is not configured" unless user.google_drive_connected? && user.google_drive_folder_id.present?
      raise ArgumentError, "Media backups are turned off in Privacy settings" unless user.ensure_app_setting!.include_media_in_backups?
    end

    def relocate_remote_folder_if_structure_changed!
      return if effective_remote_folder_id.blank?

      root_changed = effective_drive_folder_id.present? && effective_drive_folder_id != user.google_drive_folder_id
      path_changed = stored_folder_path_signature.present? && stored_folder_path_signature != current_folder_path_signature
      return unless root_changed || path_changed

      parent_folder_id = ensure_export_parent_folder_id
      remote_folder = drive_service.get_file(effective_remote_folder_id, fields: "id,name,parents")
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
    rescue Google::Apis::ClientError
      reset_remote_references!
    end

    def ensure_remote_folder!
      return effective_remote_folder_id if effective_remote_folder_id.present?

      folder = Drive::EnsureFolderPath.new(
        user: user,
        parent_id: ensure_export_parent_folder_id,
        segments: [remote_folder_name]
      ).call

      folder.id
    end

    def ensure_export_parent_folder_id
      Drive::EnsureFolderPath.new(
        user: user,
        parent_id: user.google_drive_folder_id,
        segments: [CAPTURES_FOLDER_NAME]
      ).call.id
    end

    def export_folder_segments
      [CAPTURES_FOLDER_NAME, remote_folder_name]
    end

    def current_folder_path_signature
      export_folder_segments.join(" / ")
    end

    def current_folder_path_display
      export_folder_segments.join(" / ")
    end

    def remote_folder_name
      Drive::ExportLayout.record_folder_name(capture)
    end

    def download_image
      tempfile = Tempfile.new(["drive-export", File.extname(capture.original_filename.to_s)])
      storage.bucket(capture.storage_bucket).file(capture.storage_object_key).download(tempfile.path)
      tempfile
    end

    def upsert_capture_image(folder_id:, image_file:)
      upsert_file(
        file_id: effective_image_file_id,
        folder_id: folder_id,
        file_name: capture_filename,
        upload_source: image_file.path,
        content_type: capture.content_type
      )
    end

    def sync_latest_ocr_text(folder_id)
      text_body = latest_ocr_result&.cleaned_text.to_s
      if text_body.present?
        upsert_text_file(
          file_id: effective_text_file_id,
          folder_id: folder_id,
          file_name: LATEST_OCR_FILE_NAME,
          content: text_body,
          content_type: "text/plain"
        )
      else
        delete_remote_file(effective_text_file_id)
        nil
      end
    end

    def sync_uploaded_attachments(folder_id)
      stored_mapping = effective_attachment_file_ids
      uploaded_attachments_by_key = uploaded_attachments.index_by { |attachment| attachment.id.to_s }

      (stored_mapping.keys - uploaded_attachments_by_key.keys).each do |removed_attachment_id|
        delete_remote_file(stored_mapping[removed_attachment_id])
      end

      next_mapping = stored_mapping.slice(*uploaded_attachments_by_key.keys)
      attachments_folder_id = uploaded_attachments_by_key.any? ? ensure_asset_folder(folder_id, ATTACHMENTS_FOLDER_NAME) : nil

      uploaded_attachments.each_with_index do |attachment, index|
        next_mapping[attachment.id.to_s] = upsert_blob_file(
          file_id: stored_mapping[attachment.id.to_s],
          folder_id: attachments_folder_id,
          blob: attachment.asset.blob,
          file_name: attachment_file_name(attachment, index + 1)
        )
      end

      next_mapping
    end

    def manifest_payload
      {
        "app" => "Inkcreate",
        "package_type" => "capture",
        "package_version" => PACKAGE_VERSION,
        "exported_at" => Time.current.iso8601,
        "capture" => capture_payload,
        "latest_ocr_result" => latest_ocr_result_payload,
        "ocr_results" => ocr_results_payload,
        "latest_ai_summary" => latest_ai_summary_payload,
        "ai_summaries" => ai_summaries_payload,
        "attachments" => attachments_payload,
        "tasks" => tasks_payload,
        "revisions" => revisions_payload,
        "reference_links" => reference_links_payload
      }
    end

    def capture_payload
      {
        "id" => capture.id,
        "title" => capture.title,
        "display_title" => capture.display_title,
        "description" => capture.description,
        "page_type" => capture.page_type,
        "status" => capture.status,
        "ocr_status" => capture.ocr_status,
        "ai_status" => capture.ai_status,
        "backup_status" => capture.backup_status,
        "sync_status" => capture.sync_status,
        "original_filename" => capture.original_filename,
        "content_type" => capture.content_type,
        "byte_size" => capture.byte_size,
        "checksum" => capture.checksum,
        "captured_at" => capture.captured_at&.iso8601,
        "processed_at" => capture.processed_at&.iso8601,
        "favorite" => capture.favorite,
        "archived_at" => capture.archived_at&.iso8601,
        "classification_confidence" => capture.classification_confidence&.to_f,
        "meeting_label" => capture.meeting_label,
        "conference_label" => capture.conference_label,
        "project_label" => capture.project_label,
        "search_text" => capture.search_text,
        "metadata" => capture.metadata,
        "drive_sync_mode" => capture.drive_sync_mode,
        "tags" => capture_tags,
        "context" => capture_context_payload,
        "source_image" => {
          "filename" => capture_filename,
          "content_type" => capture.content_type,
          "byte_size" => capture.byte_size
        },
        "created_at" => capture.created_at.iso8601,
        "updated_at" => capture.updated_at.iso8601
      }
    end

    def capture_context_payload
      {
        "project" => capture_project_payload,
        "daily_log" => capture_daily_log_payload,
        "physical_page" => capture_physical_page_payload,
        "page_template" => capture_page_template_payload
      }
    end

    def capture_project_payload
      return nil if capture.project.blank?

      {
        "id" => capture.project.id,
        "title" => capture.project.title,
        "slug" => capture.project.slug,
        "archived_at" => capture.project.archived_at&.iso8601
      }
    end

    def capture_daily_log_payload
      return nil if capture.daily_log.blank?

      {
        "id" => capture.daily_log.id,
        "title" => capture.daily_log.display_title,
        "entry_date" => capture.daily_log.entry_date.iso8601
      }
    end

    def capture_physical_page_payload
      return nil if capture.physical_page.blank?

      {
        "id" => capture.physical_page.id,
        "page_number" => capture.physical_page.page_number,
        "label" => capture.physical_page.label,
        "template_type" => capture.physical_page.template_type,
        "active" => capture.physical_page.active
      }
    end

    def capture_page_template_payload
      return nil if capture.page_template.blank?

      {
        "id" => capture.page_template.id,
        "key" => capture.page_template.key,
        "name" => capture.page_template.name,
        "description" => capture.page_template.description,
        "classifier_version" => capture.page_template.classifier_version
      }
    end

    def latest_ocr_result_payload
      return nil if latest_ocr_result.blank?

      ocr_result_payload(latest_ocr_result)
    end

    def ocr_results_payload
      ocr_results.map { |result| ocr_result_payload(result) }
    end

    def ocr_result_payload(result)
      {
        "id" => result.id,
        "ocr_job_id" => result.ocr_job_id,
        "provider" => result.provider,
        "language" => result.language,
        "mean_confidence" => result.mean_confidence&.to_f,
        "cleaned_text" => result.cleaned_text,
        "raw_text" => result.raw_text,
        "metadata" => result.metadata,
        "created_at" => result.created_at.iso8601,
        "updated_at" => result.updated_at.iso8601
      }
    end

    def latest_ai_summary_payload
      return nil if latest_ai_summary.blank?

      ai_summary_payload(latest_ai_summary)
    end

    def ai_summaries_payload
      ai_summaries.map { |summary| ai_summary_payload(summary) }
    end

    def ai_summary_payload(summary)
      {
        "id" => summary.id,
        "provider" => summary.provider,
        "summary" => summary.summary,
        "bullets" => summary.bullets,
        "tasks_extracted" => summary.tasks_extracted,
        "entities" => summary.entities,
        "raw_payload" => summary.raw_payload,
        "created_at" => summary.created_at.iso8601,
        "updated_at" => summary.updated_at.iso8601
      }
    end

    def attachments_payload
      capture_attachments.map do |attachment|
        payload = {
          "id" => attachment.id,
          "attachment_type" => attachment.attachment_type,
          "title" => attachment.title,
          "display_title" => attachment.display_title,
          "url" => attachment.url,
          "content_type" => attachment.content_type,
          "byte_size" => attachment.byte_size,
          "metadata" => attachment.metadata,
          "stored_file" => attachment.stored_file?,
          "created_at" => attachment.created_at.iso8601,
          "updated_at" => attachment.updated_at.iso8601
        }

        if attachment.asset.attached?
          payload["asset"] = {
            "filename" => attachment.asset.blob.filename.to_s,
            "content_type" => attachment.asset.blob.content_type,
            "byte_size" => attachment.asset.blob.byte_size
          }
        end

        payload
      end
    end

    def tasks_payload
      capture_tasks.map do |task|
        {
          "id" => task.id,
          "title" => task.title,
          "description" => task.description,
          "priority" => task.priority,
          "severity" => task.severity,
          "completed" => task.completed,
          "completed_at" => task.completed_at&.iso8601,
          "due_date" => task.due_date&.iso8601,
          "reminder_at" => task.reminder_at&.iso8601,
          "reminder_recurrence" => task.reminder_recurrence,
          "tags" => task.tags_array,
          "project_id" => task.project_id,
          "daily_log_id" => task.daily_log_id,
          "link" => {
            "type" => task.link_type,
            "resource_id" => task.link_resource_id,
            "label" => task.link_label,
            "notebook_id" => task.link_notebook_id,
            "chapter_id" => task.link_chapter_id,
            "page_id" => task.link_page_id
          },
          "subtasks" => task.task_subtasks.ordered.map do |subtask|
            {
              "id" => subtask.id,
              "title" => subtask.title,
              "completed" => subtask.completed,
              "completed_at" => subtask.completed_at&.iso8601,
              "position" => subtask.position
            }
          end,
          "created_at" => task.created_at.iso8601,
          "updated_at" => task.updated_at.iso8601
        }
      end
    end

    def revisions_payload
      capture_revisions.map do |revision|
        {
          "id" => revision.id,
          "revision_number" => revision.revision_number,
          "metadata" => revision.metadata,
          "created_at" => revision.created_at.iso8601,
          "updated_at" => revision.updated_at.iso8601
        }
      end
    end

    def reference_links_payload
      {
        "outgoing" => outgoing_reference_links.map { |link| reference_link_payload(link, direction: "outgoing") },
        "incoming" => incoming_reference_links.map { |link| reference_link_payload(link, direction: "incoming") }
      }
    end

    def reference_link_payload(link, direction:)
      related_capture = direction == "outgoing" ? link.target_capture : link.source_capture

      {
        "id" => link.id,
        "relation_type" => link.relation_type,
        "related_capture" => {
          "id" => related_capture.id,
          "title" => related_capture.title,
          "display_title" => related_capture.display_title
        },
        "created_at" => link.created_at.iso8601,
        "updated_at" => link.updated_at.iso8601
      }
    end

    def export_metadata
      drive_sync.metadata.to_h.except(
        REMOTE_FOLDER_ID_KEY,
        REMOTE_MANIFEST_FILE_ID_KEY,
        REMOTE_ATTACHMENT_FILE_IDS_KEY
      ).merge(
        "package_type" => "capture",
        "package_version" => PACKAGE_VERSION,
        "drive_folder_id" => user.google_drive_folder_id,
        "folder_path" => export_folder_segments,
        "folder_path_signature" => current_folder_path_signature,
        "capture_title" => capture.display_title,
        "exported_at" => Time.current.iso8601
      )
    end

    def backup_record_metadata
      base_metadata = linked_backup_record.present? ? linked_backup_record.metadata.to_h : {}

      base_metadata.merge(
        "package_type" => "capture",
        "package_version" => PACKAGE_VERSION,
        "folder_path" => export_folder_segments,
        "folder_path_signature" => current_folder_path_signature
      )
    end

    def capture_filename
      base = capture.title.presence || File.basename(capture.original_filename.to_s, ".*")
      extension = File.extname(capture.original_filename.to_s)
      return capture.original_filename if base.blank?

      "#{base}#{extension}"
    end

    def attachment_file_name(attachment, index)
      blob = attachment.asset.blob
      extension = File.extname(blob.filename.to_s).presence || ""
      base_name = attachment.title.to_s.parameterize.presence || File.basename(blob.filename.to_s, extension).parameterize.presence || attachment.attachment_type
      format("attachment-%<index>02d-%<name>s%<extension>s", index: index, name: base_name, extension: extension)
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

    def upsert_text_file(file_id:, folder_id:, file_name:, content:, content_type:)
      upsert_file(
        file_id: file_id,
        folder_id: folder_id,
        file_name: file_name,
        upload_source: StringIO.new(content),
        content_type: content_type
      )
    end

    def upsert_file(file_id:, folder_id:, file_name:, upload_source:, content_type:)
      metadata = Google::Apis::DriveV3::File.new(name: file_name)

      if file_id.present?
        existing_file = drive_service.get_file(file_id, fields: "id,parents")
        update_options = { upload_source: upload_source, content_type: content_type, fields: "id" }
        existing_parent_id = Array(existing_file.parents).first
        if existing_parent_id != folder_id
          update_options[:add_parents] = folder_id
          update_options[:remove_parents] = existing_parent_id if existing_parent_id.present?
        end

        drive_service.update_file(file_id, metadata, **update_options)
        file_id
      else
        metadata.parents = [folder_id]
        drive_service.create_file(metadata, upload_source: upload_source, content_type: content_type, fields: "id").id
      end
    rescue Google::Apis::ClientError
      metadata.parents = [folder_id]
      drive_service.create_file(metadata, upload_source: upload_source, content_type: content_type, fields: "id").id
    end

    def delete_remote_file(file_id)
      return if file_id.blank?

      drive_service.delete_file(file_id)
    rescue Google::Apis::ClientError
      nil
    end

    def ensure_asset_folder(folder_id, folder_name)
      Drive::EnsureFolderPath.new(
        user: user,
        parent_id: folder_id,
        segments: [folder_name]
      ).call.id
    end

    def reset_remote_references!
      drive_sync.update!(
        image_file_id: nil,
        text_file_id: nil,
        metadata: drive_sync.metadata.to_h.except(
          REMOTE_FOLDER_ID_KEY,
          REMOTE_MANIFEST_FILE_ID_KEY,
          REMOTE_ATTACHMENT_FILE_IDS_KEY
        )
      )
    end

    def stored_folder_path_signature
      drive_sync.metadata.to_h["folder_path_signature"].presence || previous_export_metadata["folder_path_signature"].presence
    end

    def effective_remote_folder_id
      drive_sync.metadata.to_h[REMOTE_FOLDER_ID_KEY].presence || previous_export_metadata[REMOTE_FOLDER_ID_KEY].presence
    end

    def effective_manifest_file_id
      drive_sync.metadata.to_h[REMOTE_MANIFEST_FILE_ID_KEY].presence || previous_export_metadata[REMOTE_MANIFEST_FILE_ID_KEY].presence
    end

    def effective_attachment_file_ids
      current_mapping = drive_sync.metadata.to_h[REMOTE_ATTACHMENT_FILE_IDS_KEY]
      return current_mapping.to_h.stringify_keys if current_mapping.present?

      previous_export_metadata.fetch(REMOTE_ATTACHMENT_FILE_IDS_KEY, {}).to_h.stringify_keys
    end

    def effective_image_file_id
      drive_sync.image_file_id.presence || previous_drive_sync&.image_file_id.presence
    end

    def effective_text_file_id
      drive_sync.text_file_id.presence || previous_drive_sync&.text_file_id.presence
    end

    def effective_drive_folder_id
      previous_drive_sync&.drive_folder_id.presence || drive_sync.metadata.to_h["drive_folder_id"].presence || drive_sync.drive_folder_id
    end

    def previous_export_metadata
      @previous_export_metadata ||= previous_drive_sync&.metadata.to_h || {}
    end

    def previous_drive_sync
      @previous_drive_sync ||= capture.drive_syncs
        .where.not(id: drive_sync.id)
        .where(status: :succeeded)
        .order(exported_at: :desc, created_at: :desc)
        .first
    end

    def linked_backup_record
      backup_record_id = drive_sync.metadata&.fetch("backup_record_id", nil)
      return if backup_record_id.blank?

      @linked_backup_record ||= capture.backup_records.find_by(id: backup_record_id)
    end

    def latest_ocr_result
      @latest_ocr_result ||= capture.latest_ocr_result
    end

    def ocr_results
      @ocr_results ||= capture.ocr_results.order(created_at: :asc, id: :asc).to_a
    end

    def latest_ai_summary
      @latest_ai_summary ||= capture.latest_ai_summary
    end

    def ai_summaries
      @ai_summaries ||= capture.ai_summaries.recent_first.reverse
    end

    def capture_attachments
      @capture_attachments ||= capture.attachments.includes(asset_attachment: :blob).recent_first.reverse
    end

    def uploaded_attachments
      @uploaded_attachments ||= capture_attachments.select(&:stored_file?)
    end

    def capture_tasks
      @capture_tasks ||= capture.tasks.includes(:task_subtasks).recent_first.reverse
    end

    def capture_revisions
      @capture_revisions ||= capture.capture_revisions.recent_first.reverse
    end

    def outgoing_reference_links
      @outgoing_reference_links ||= capture.outgoing_reference_links.includes(:target_capture).order(created_at: :asc).to_a
    end

    def incoming_reference_links
      @incoming_reference_links ||= capture.incoming_reference_links.includes(:source_capture).order(created_at: :asc).to_a
    end

    def capture_tags
      @capture_tags ||= capture.tags.order(:name).pluck(:name)
    end

    def drive_service
      @drive_service ||= ClientFactory.build(user: user)
    end

    def storage
      @storage ||= Google::Cloud::Storage.new(project_id: ENV.fetch("GCP_PROJECT_ID"))
    end
  end
end
