class BrowserController < ActionController::Base
  DEVICE_COOKIE_KEY = :inkcreate_device_id
  WORKSPACE_CONTROLLERS = %w[
    home
    notebooks
    chapters
    pages
    notepad_entries
    capture_studio
    inbox
    projects
    daily_logs
    captures
    search
    tasks
    reminders
    library
    settings
    settings/backup
    settings/privacy
  ].freeze

  include ActionController::Cookies
  include ActionController::RequestForgeryProtection
  include ActiveStorage::SetCurrent
  include Devise::Controllers::Helpers
  include CurrentUserContext
  include RequestTimeZoneContext

  protect_from_forgery with: :exception
  layout :browser_layout

  helper_method :current_user,
    :user_signed_in?,
    :workspace_header_page?,
    :workspace_layout_page?,
    :google_auth_available?,
    :password_auth_available?,
    :google_only_auth_mode?,
    :public_auth_entry_path,
    :versioned_public_asset_path,
    :current_device_record,
    :reminder_relative_time,
    :reminder_source_label,
    :reminder_fire_at_local_value,
    :voice_note_duration_label
  before_action :set_request_context
  before_action :promote_browser_session_flash
  before_action :track_current_device, if: :user_signed_in?

  rescue_from ActiveRecord::RecordNotFound do
    head :not_found
  end

  def reminder_relative_time(reminder)
    distance = helpers.distance_of_time_in_words(Time.current, reminder.fire_at)

    if reminder.fire_at.future?
      "in #{distance}"
    else
      "#{distance} ago"
    end
  end

  def reminder_source_label(reminder)
    if reminder.target.is_a?(TodoItem)
      "From to-do: #{reminder.target.content}"
    else
      "Standalone"
    end
  end

  def reminder_fire_at_local_value(reminder)
    return reminder.fire_at.in_time_zone.strftime("%Y-%m-%dT%H:%M") if reminder.fire_at.present?
    return unless reminder.new_record? && reminder.errors.empty?

    1.hour.from_now.in_time_zone.strftime("%Y-%m-%dT%H:%M")
  end

  def voice_note_duration_label(duration_seconds)
    total_seconds = duration_seconds.to_i
    hours = total_seconds / 3600
    minutes = (total_seconds % 3600) / 60
    seconds = total_seconds % 60

    if hours.positive?
      format("%d:%02d:%02d", hours, minutes, seconds)
    else
      format("%02d:%02d", minutes, seconds)
    end
  end

  def google_auth_available?
    GlobalSetting.google_auth_configured?
  end

  def password_auth_available?
    GlobalSetting.password_auth_enabled?
  end

  def google_only_auth_mode?
    google_auth_available? && !password_auth_available?
  end

  def public_auth_entry_path
    google_only_auth_mode? ? browser_sign_in_path : browser_sign_up_path
  end

  private

  def set_request_context
    Current.request_id = request.request_id
    Current.user = current_user
    Current.device = current_device_record if user_signed_in? && Device.schema_ready?
    response.set_header("X-Request-Id", request.request_id)
  end

  def require_authenticated_user!
    redirect_to browser_sign_in_path, alert: "Sign in to continue." unless user_signed_in?
  end

  def require_admin!
    redirect_to dashboard_path, alert: "Admin access required." unless current_user&.admin?
  end

  def post_auth_redirect_for(user)
    user.admin? ? admin_dashboard_path : dashboard_path
  end

  def workspace_header_page?
    WORKSPACE_CONTROLLERS.include?(controller_path)
  end

  def workspace_layout_page?
    user_signed_in? && WORKSPACE_CONTROLLERS.include?(controller_path)
  end

  def browser_layout
    workspace_layout_page? ? "workspace" : "landing"
  end

  def current_device_record
    return unless user_signed_in?
    return unless Device.schema_ready?

    @current_device_record ||= begin
      device = current_user.devices.find_by(id: cookies.signed[DEVICE_COOKIE_KEY])
      normalized_user_agent = request.user_agent.to_s.presence || "Unknown browser"

      unless device
        device = current_user.devices.create!(
          user_agent: normalized_user_agent,
          last_seen_at: Time.current
        )

        cookies.permanent.signed[DEVICE_COOKIE_KEY] = {
          value: device.id,
          httponly: true,
          same_site: :lax,
          secure: Rails.env.production?
        }
      end

      device
    end
  rescue ActiveRecord::StatementInvalid, PG::UndefinedTable
    nil
  end

  def versioned_public_asset_path(path)
    logical_path = path.to_s.delete_prefix("/")
    absolute_path = Rails.root.join("public", logical_path)

    return "/#{logical_path}" unless absolute_path.file?

    "/#{logical_path}?v=#{absolute_path.mtime.to_i}"
  end

  def promote_browser_session_flash
    flash.now[:notice] = session.delete(:browser_notice) if session[:browser_notice].present?
    flash.now[:alert] = session.delete(:browser_alert) if session[:browser_alert].present?
  end

  def track_current_device
    return unless Device.schema_ready?

    device = current_device_record
    return unless device

    updates = {
      last_seen_at: Time.current
    }

    if request.user_agent.present? && device.user_agent != request.user_agent.to_s
      updates[:user_agent] = request.user_agent.to_s
    end

    device.update_columns(updates.merge(updated_at: Time.current))
  rescue ActiveRecord::StatementInvalid, PG::UndefinedTable
    nil
  end
end
