class Device < ApplicationRecord
  belongs_to :user

  validates :user_agent, presence: true
  validates :push_endpoint, uniqueness: true, allow_blank: true

  scope :recent_first, -> { order(last_seen_at: :desc, updated_at: :desc, created_at: :desc) }
  scope :enabled_for_push, -> { where(push_enabled: true).where.not(push_endpoint: [nil, ""]) }

  def display_label
    label.presence || inferred_label
  end

  def enable_push!(endpoint:, p256dh_key:, auth_key:, device_label: nil)
    update!(
      label: device_label.presence || label,
      push_enabled: true,
      push_endpoint: endpoint,
      push_p256dh_key: p256dh_key,
      push_auth_key: auth_key,
      last_seen_at: Time.current
    )
  end

  def disable_push!
    update!(
      push_enabled: false,
      push_endpoint: nil,
      push_p256dh_key: nil,
      push_auth_key: nil
    )
  end

  def touch_last_seen!
    touch(:last_seen_at)
  end

  private

  def inferred_label
    agent = user_agent.to_s.downcase

    return "iPhone" if agent.include?("iphone")
    return "iPad" if agent.include?("ipad")
    return "Android phone" if agent.include?("android") && agent.include?("mobile")
    return "Android tablet" if agent.include?("android")
    return "Mac" if agent.include?("mac os")
    return "Windows PC" if agent.include?("windows")
    return "Linux PC" if agent.include?("linux")

    "This device"
  end
end
