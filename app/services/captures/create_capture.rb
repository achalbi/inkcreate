module Captures
  class CreateCapture
    def initialize(user:, params:)
      @user = user
      @params = params.deep_symbolize_keys
    end

    def call
      bucket = ENV.fetch("GCS_UPLOAD_BUCKET")
      file = Uploads::ObjectVerifier.new(
        bucket: bucket,
        object_key: params.fetch(:object_key),
        user_id: user.id
      ).call

      capture = nil

      Capture.transaction do
        capture = user.captures.create!(
          notebook: notebook,
          project: project,
          daily_log: daily_log,
          physical_page: physical_page,
          page_template: page_template,
          title: params[:title],
          description: params[:description],
          page_type: page_type,
          content_type: file.content_type,
          original_filename: params[:original_filename].presence || File.basename(file.name),
          byte_size: file.size,
          checksum: file.md5,
          storage_bucket: bucket,
          storage_object_key: file.name,
          captured_at: params[:captured_at],
          meeting_label: params[:meeting_label],
          conference_label: params[:conference_label],
          project_label: params[:project_label],
          drive_sync_mode: params[:drive_sync_mode].presence || :manual,
          status: :uploaded,
          ocr_status: :not_started,
          ai_status: :not_started,
          backup_status: :local_only,
          sync_status: :synced,
          last_synced_at: Time.current,
          client_draft_id: params[:client_draft_id],
          metadata: params[:metadata] || {}
        )

        assign_tags!(capture)
        capture.capture_revisions.create!(revision_number: 1, metadata: { created_from: "capture_upload" })
      end

      Observability::EventLogger.info(
        event: "capture.created",
        payload: {
          capture_id: capture.id,
          notebook_id: notebook&.id,
          project_id: project&.id,
          daily_log_id: daily_log&.id,
          object_key: capture.storage_object_key
        }
      )

      capture
    end

    private

    attr_reader :user, :params

    def notebook
      return if params[:notebook_id].blank?

      user.notebooks.find(params[:notebook_id])
    end

    def project
      return if params[:project_id].blank?

      user.projects.find(params[:project_id])
    end

    def daily_log
      return user.daily_logs.find(params[:daily_log_id]) if params[:daily_log_id].present?
      return if params[:save_destination] != "today"

      user.daily_logs.find_or_create_by!(entry_date: Time.zone.today) do |daily_log|
        daily_log.title = "Today"
      end
    end

    def physical_page
      return if params[:physical_page_id].blank?

      user.physical_pages.find(params[:physical_page_id])
    end

    def page_template
      return if params[:page_template_key].blank?

      PageTemplate.find_by!(key: params[:page_template_key])
    end

    def page_type
      params[:page_type].presence || page_template&.key || "blank"
    end

    def assign_tags!(capture)
      normalized_tag_names.each do |tag_name|
        tag = user.tags.find_or_create_by!(name: tag_name)
        capture.capture_tags.find_or_create_by!(tag: tag)
      end
    end

    def normalized_tag_names
      Array(params[:tags]).flat_map { |value| value.to_s.split(",") }.map(&:strip).reject(&:blank?).uniq
    end
  end
end
