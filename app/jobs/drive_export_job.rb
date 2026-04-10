class DriveExportJob < ApplicationJob
  queue_as :low

  retry_on StandardError, wait: :polynomially_longer, attempts: 8

  def perform(drive_sync_id)
    drive_sync = DriveSync.find(drive_sync_id)
    Current.request_id = job_id
    Current.user = drive_sync.user

    Drive::ExportCapture.new(drive_sync: drive_sync).call
  ensure
    Current.reset
  end
end
