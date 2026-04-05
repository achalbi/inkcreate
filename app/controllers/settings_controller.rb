class SettingsController < BrowserController
  before_action :require_authenticated_user!
  before_action :load_settings_dashboard

  def show
    @settings_user = current_user
  end

  def update
    @settings_user = current_user

    if @settings_user.update(settings_user_params.merge(time_zone_locked: true))
      redirect_to settings_path, notice: "Time zone updated."
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def load_settings_dashboard
    @app_setting = current_user.ensure_app_setting!
    @storage_stats = {
      captures: current_user.captures.count,
      attachments: current_user.attachments.count,
      pending_sync_jobs: current_user.sync_jobs.status_pending.count
    }
    @detected_time_zone_name = browser_time_zone_name.presence
    @selected_time_zone = current_user.time_zone_locked? ? current_user.time_zone : (@detected_time_zone_name || current_user.time_zone)
  end

  def settings_user_params
    params.require(:user).permit(:time_zone)
  end
end
