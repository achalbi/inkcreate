module Admin
  class DashboardController < BaseController
    def show
      inflight_statuses = [
        Capture.statuses.fetch("uploaded"),
        Capture.statuses.fetch("queued"),
        Capture.statuses.fetch("processing")
      ]

      @user_count = User.count
      @admin_count = User.admin.count
      @standard_user_count = User.user.count
      @connected_drive_count = User.where.not(google_drive_connected_at: nil).count
      @project_count = Project.count
      @daily_log_count = DailyLog.count
      @notebook_count = Notebook.count
      @capture_count = Capture.count
      @captures_this_week = Capture.where(created_at: 7.days.ago..Time.current).count
      @new_users_this_week = User.where(created_at: 7.days.ago..Time.current).count
      @ready_capture_count = Capture.status_ready.count
      @active_capture_count = Capture.where(status: inflight_statuses).count
      @failed_capture_count = Capture.status_failed.count
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
      @open_task_count = Task.open.count
      @tag_count = Tag.count
      @recent_users = User.order(created_at: :desc).limit(6)
      @recent_captures = Capture.includes(:user, :notebook, :project, :daily_log).recent_first.limit(6)
    end
  end
end
