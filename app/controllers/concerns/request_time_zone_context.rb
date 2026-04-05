require "cgi"

module RequestTimeZoneContext
  extend ActiveSupport::Concern

  TIME_ZONE_ALIASES = {
    "Asia/Calcutta" => "Asia/Kolkata"
  }.freeze

  included do
    around_action :use_effective_time_zone
    helper_method :effective_time_zone_name
  end

  private

  def use_effective_time_zone(&block)
    Time.use_zone(effective_time_zone_name, &block)
  end

  def effective_time_zone_name
    @effective_time_zone_name ||= begin
      zone_name =
        if current_user&.time_zone_locked?
          current_user.time_zone.presence || browser_time_zone_name.presence || "UTC"
        else
          browser_time_zone_name.presence || current_user&.time_zone.presence || "UTC"
        end

      ActiveSupport::TimeZone[zone_name]&.name || "UTC"
    end
  end

  def browser_time_zone_name
    zone_name = normalized_time_zone_name(raw_browser_time_zone_cookie_value)
    return if zone_name.blank?

    ActiveSupport::TimeZone[zone_name]&.name
  end

  def raw_browser_time_zone_cookie_value
    cookies[:browser_time_zone].presence
  end

  def normalized_time_zone_name(zone_name)
    decoded_zone_name = CGI.unescape(zone_name.to_s).presence
    return if decoded_zone_name.blank?

    canonical_zone_name = TIME_ZONE_ALIASES.fetch(decoded_zone_name, decoded_zone_name)
    ActiveSupport::TimeZone[canonical_zone_name]&.name
  end
end
