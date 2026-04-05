module Admin
  class BaseController < BrowserController
    layout "admin"

    before_action :require_authenticated_user!
    before_action :require_admin!
    before_action :set_admin_shell_metrics

    private

    def set_admin_shell_metrics
      inflight_statuses = [
        Capture.statuses.fetch("uploaded"),
        Capture.statuses.fetch("queued"),
        Capture.statuses.fetch("processing")
      ]

      issue_count =
        Capture.status_failed.count +
        OcrJob.status_failed.count +
        BackupRecord.status_failed.count +
        SyncJob.status_failed.count +
        SyncJob.status_conflict.count +
        DriveSync.status_failed.count

      @admin_shell_metrics = {
        users: User.count,
        captures: Capture.count,
        inflight: Capture.where(status: inflight_statuses).count,
        issues: issue_count
      }
    end
  end
end
