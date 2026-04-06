module Async
  class Dispatcher
    def self.enqueue_ocr(ocr_job_id)
      dispatch(
        queue: ENV.fetch("CLOUD_TASKS_OCR_QUEUE", "ocr-jobs"),
        path: "/internal/ocr_jobs/#{ocr_job_id}/perform",
        job_fallback: -> { OcrCaptureJob.perform_later(ocr_job_id) }
      )
    end

    def self.enqueue_drive_export(drive_sync_id)
      dispatch(
        queue: ENV.fetch("CLOUD_TASKS_DRIVE_QUEUE", "drive-sync-jobs"),
        path: "/internal/drive_syncs/#{drive_sync_id}/perform",
        job_fallback: -> { DriveExportJob.perform_later(drive_sync_id) }
      )
    end

    def self.enqueue_record_export(google_drive_export_id)
      dispatch(
        queue: ENV.fetch("CLOUD_TASKS_DRIVE_QUEUE", "drive-sync-jobs"),
        path: "/internal/google_drive_exports/#{google_drive_export_id}/perform",
        job_fallback: -> { GoogleDriveExportJob.perform_later(google_drive_export_id) }
      )
    end

    def self.dispatch(queue:, path:, job_fallback:)
      if backend == "cloud_tasks"
        begin
          CloudTasksEnqueuer.new.enqueue(queue: queue, path: path)
        rescue StandardError => error
          Observability::EventLogger.info(
            event: "async.cloud_tasks_fallback",
            payload: {
              queue: queue,
              path: path,
              error_class: error.class.name,
              error_message: error.message
            }
          )
          job_fallback.call
        end
      else
        job_fallback.call
      end
    end

    def self.backend
      ENV.fetch("JOB_BACKEND", "sidekiq")
    end

    private_class_method :dispatch
  end
end
