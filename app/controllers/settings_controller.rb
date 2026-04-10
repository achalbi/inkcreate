class SettingsController < BrowserController
  before_action :require_authenticated_user!
  before_action :load_settings_dashboard

  def show
    @settings_user = current_user.dup
    @settings_user.time_zone = @selected_time_zone if @selected_time_zone.present?
  end

  def update
    @settings_user = current_user

    if @settings_user.update(normalized_settings_user_params.merge(time_zone_locked: true))
      redirect_to settings_path, notice: "Time zone updated."
    else
      @selected_time_zone = canonical_time_zone_name(@settings_user.time_zone) || @selected_time_zone
      render :show, status: :unprocessable_entity
    end
  end

  private

  def load_settings_dashboard
    @app_setting = current_user.ensure_app_setting!
    @backup_records = current_user.backup_records.recent_first.limit(20)
    @devices_available = Device.schema_ready?
    @devices = @devices_available ? current_user.devices.recent_first : []
    @current_device = @devices_available ? current_device_record : nil
    @web_push_available = @devices_available && WebPushDeliverer.configured?
    @web_push_public_key = @web_push_available ? WebPushDeliverer.public_key : nil
    @storage_stats = {
      captures: current_user.captures.count,
      attachments: current_user.attachments.count,
      pending_sync_jobs: current_user.sync_jobs.status_pending.count
    }
    @detected_time_zone_name = canonical_time_zone_name(browser_time_zone_name.presence)
    @selected_time_zone = @detected_time_zone_name || canonical_time_zone_name(current_user.time_zone)
  end

  def settings_user_params
    params.require(:user).permit(:time_zone)
  end

  def normalized_settings_user_params
    attributes = settings_user_params.to_h
    attributes[:time_zone] = canonical_time_zone_name(attributes[:time_zone]) if attributes[:time_zone].present?
    attributes
  end

  def canonical_time_zone_name(zone_name)
    ActiveSupport::TimeZone[zone_name]&.tzinfo&.name || zone_name.presence
  end
end
