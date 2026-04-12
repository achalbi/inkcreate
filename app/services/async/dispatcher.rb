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

    def self.enqueue_reminder(reminder_id, fire_at:)
      dispatch_at = fire_at.future? ? fire_at : nil

      dispatch(
        queue: ENV.fetch("CLOUD_TASKS_REMINDERS_QUEUE", "reminder-jobs"),
        path: "/internal/reminders/#{reminder_id}/perform",
        schedule_at: dispatch_at,
        job_fallback: lambda {
          if dispatch_at.present?
            DispatchDueRemindersJob.set(wait_until: dispatch_at).perform_later(reminder_id)
          else
            DispatchDueRemindersJob.perform_later(reminder_id)
          end
        }
      )
    end

    def self.dispatch(queue:, path:, job_fallback:, schedule_at: nil)
      if backend == "cloud_tasks"
        begin
          CloudTasksEnqueuer.new.enqueue(queue: queue, path: path, schedule_at: schedule_at)
        rescue StandardError => error
          Observability::EventLogger.info(
            event: "async.cloud_tasks_fallback",
            payload: {
              queue: queue,
              path: path,
              schedule_at: schedule_at,
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
