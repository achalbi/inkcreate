module Internal
  class DriveSyncsController < BaseController
    def perform
      drive_sync = DriveSync.find(params[:id])
      Current.user = drive_sync.user
      Drive::ExportCapture.new(drive_sync: drive_sync).call
      head :accepted
    ensure
      Current.reset
    end
  end
end
