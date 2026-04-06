module Ocr
  class Pipeline
    def initialize(ocr_job:)
      @ocr_job = ocr_job
      @capture = ocr_job.capture
    end

    def call
      ocr_job.update!(status: :running, started_at: Time.current, attempts: ocr_job.attempts + 1)
      capture.update!(status: :processing, ocr_status: :processing)

      source_file = download_source_file
      processed_file = ImagePreprocessor.new(source_path: source_file.path).call
      provider = ProviderFactory.build(ocr_job.provider)
      provider_result = provider.call(image_path: processed_file.path)
      classification = TemplateClassifier.new(capture: capture, cleaned_text: provider_result.cleaned_text).call

      Capture.transaction do
        ocr_result = capture.ocr_results.create!(
          ocr_job: ocr_job,
          provider: ocr_job.provider,
          raw_text: provider_result.raw_text,
          cleaned_text: provider_result.cleaned_text,
          mean_confidence: provider_result.mean_confidence,
          language: provider_result.language,
          metadata: provider_result.metadata
        )

        Search::CaptureIndexer.new(capture: capture, ocr_result: ocr_result).call

        capture.update!(
          page_template: classification.page_template,
          page_type: classification.page_template&.key || capture.page_type,
          classification_confidence: classification.confidence,
          status: :ready,
          ocr_status: :completed,
          processed_at: Time.current
        )

        ocr_job.update!(status: :succeeded, finished_at: Time.current)
      end

      Observability::EventLogger.info(
        event: "ocr.completed",
        payload: { capture_id: capture.id, ocr_job_id: ocr_job.id, provider: ocr_job.provider }
      )

      if capture.drive_sync_mode_automatic? &&
         capture.user.google_drive_connected? &&
         capture.user.google_drive_folder_id.present? &&
         capture.user.ensure_app_setting!.include_photos_in_backups?
        drive_sync = capture.drive_syncs.create!(
          user: capture.user,
          drive_folder_id: capture.user.google_drive_folder_id,
          mode: :automatic,
          status: :pending
        )
        Async::Dispatcher.enqueue_drive_export(drive_sync.id)
      end
    rescue StandardError => error
      ocr_job.update!(status: :failed, finished_at: Time.current, error_message: error.message)
      capture.update!(status: :failed, ocr_status: :failed)
      Observability::EventLogger.info(
        event: "ocr.failed",
        payload: { capture_id: capture.id, ocr_job_id: ocr_job.id, error: error.message }
      )
      raise
    ensure
      source_file&.close!
      processed_file&.close!
    end

    private

    attr_reader :ocr_job, :capture

    def download_source_file
      file = Tempfile.new(["capture-source", File.extname(capture.storage_object_key)])
      storage.bucket(capture.storage_bucket).file(capture.storage_object_key).download(file.path)
      file
    end

    def storage
      @storage ||= Google::Cloud::Storage.new(project_id: ENV.fetch("GCP_PROJECT_ID"))
    end
  end
end
