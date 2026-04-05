class GoogleDriveExportJob < ApplicationJob
  queue_as :low

  retry_on StandardError, wait: :exponentially_longer, attempts: 8

  def perform(google_drive_export_id)
    google_drive_export = GoogleDriveExport.find(google_drive_export_id)
    Current.request_id = job_id
    Current.user = google_drive_export.user

    Drive::ExportRecord.new(google_drive_export: google_drive_export).call
  ensure
    Current.reset
  end
end
