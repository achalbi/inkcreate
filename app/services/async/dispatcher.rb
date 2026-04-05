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

    def self.dispatch(queue:, path:, job_fallback:)
      if backend == "cloud_tasks"
        CloudTasksEnqueuer.new.enqueue(queue:, path:)
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
