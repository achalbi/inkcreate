module Admin
  class CapturesController < BaseController
    def index
      inflight_statuses = [
        Capture.statuses.fetch("uploaded"),
        Capture.statuses.fetch("queued"),
        Capture.statuses.fetch("processing")
      ]

      @capture_count = Capture.count
      @ready_capture_count = Capture.status_ready.count
      @inflight_capture_count = Capture.where(status: inflight_statuses).count
      @failed_capture_count = Capture.status_failed.count
      @inbox_capture_count = Capture.inbox.count
      @ocr_backlog_count = Capture.where(ocr_status: [
        Capture.ocr_statuses.fetch("not_started"),
        Capture.ocr_statuses.fetch("processing")
      ]).count
      @backup_backlog_count = Capture.where(backup_status: [
        Capture.backup_statuses.fetch("pending"),
        Capture.backup_statuses.fetch("failed")
      ]).count
      @sync_issue_count = Capture.where(sync_status: [
        Capture.sync_statuses.fetch("pending"),
        Capture.sync_statuses.fetch("conflict"),
        Capture.sync_statuses.fetch("failed")
      ]).count
      @favorite_capture_count = Capture.favorited.count
      @archived_capture_count = Capture.where.not(archived_at: nil).count
      @captures = Capture.includes(:user, :project, :daily_log, :notebook, :attachments).recent_first.limit(24)
    end
  end
end
