require "test_helper"

class DeliverReminderPushJobTest < ActiveSupport::TestCase
  def build_user(email:)
    User.create!(
      email: email,
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )
  end

  test "delivers a reminder payload to the web push service" do
    user = build_user(email: "deliver-reminder@example.com")
    device = user.devices.create!(
      user_agent: "Chrome",
      push_enabled: true,
      push_endpoint: "https://example.test/push/device-1",
      push_p256dh_key: "key-1",
      push_auth_key: "auth-1",
      last_seen_at: Time.current
    )
    reminder = user.reminders.create!(
      title: "Water the plants",
      note: "Front balcony",
      fire_at: 30.minutes.from_now
    )

    deliveries = []

    WebPushDeliverer.stub(:configured?, true) do
      WebPushDeliverer.stub(:deliver, ->(device:, payload:) { deliveries << { device: device, payload: payload } }) do
        DeliverReminderPushJob.perform_now(reminder.id, device.id)
      end
    end

    assert_equal 1, deliveries.size
    assert_equal reminder.title, deliveries.first[:payload][:title]
    assert_equal reminder.destination_path, deliveries.first[:payload][:url]
  end
end
