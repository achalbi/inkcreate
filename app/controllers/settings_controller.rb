class SettingsController < BrowserController
  before_action :require_authenticated_user!

  def show
    @app_setting = current_user.ensure_app_setting!
    @storage_stats = {
      captures: current_user.captures.count,
      attachments: current_user.attachments.count,
      pending_sync_jobs: current_user.sync_jobs.status_pending.count
    }
  end
end
