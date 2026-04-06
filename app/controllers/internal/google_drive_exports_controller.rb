module Internal
  class GoogleDriveExportsController < BaseController
    def perform
      google_drive_export = GoogleDriveExport.find(params[:id])
      Current.user = google_drive_export.user
      Drive::ExportRecord.new(google_drive_export: google_drive_export).call
      head :accepted
    ensure
      Current.reset
    end
  end
end
