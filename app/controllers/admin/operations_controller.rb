module Admin
  class OperationsController < BaseController
    def show
      @ocr_active_count = OcrJob.where(status: [
        OcrJob.statuses.fetch("queued"),
        OcrJob.statuses.fetch("running")
      ]).count
      @ocr_failed_count = OcrJob.status_failed.count

      @backup_active_count = BackupRecord.where(status: [
        BackupRecord.statuses.fetch("pending"),
        BackupRecord.statuses.fetch("running")
      ]).count
      @backup_failed_count = BackupRecord.status_failed.count

      @sync_active_count = SyncJob.where(status: [
        SyncJob.statuses.fetch("pending"),
        SyncJob.statuses.fetch("running")
      ]).count
      @sync_issue_count = SyncJob.where(status: [
        SyncJob.statuses.fetch("failed"),
        SyncJob.statuses.fetch("conflict")
      ]).count

      @drive_active_count = DriveSync.where(status: [
        DriveSync.statuses.fetch("pending"),
        DriveSync.statuses.fetch("running")
      ]).count
      @drive_failed_count = DriveSync.status_failed.count

      @recent_ocr_jobs = OcrJob.includes(capture: :user).order(created_at: :desc).limit(8)
      @recent_backup_records = BackupRecord.includes(:capture, :user).recent_first.limit(8)
      @recent_sync_jobs = SyncJob.includes(:user).recent_first.limit(8)
      @recent_drive_syncs = DriveSync.includes(:capture, :user).order(created_at: :desc).limit(8)
    end
  end
end
