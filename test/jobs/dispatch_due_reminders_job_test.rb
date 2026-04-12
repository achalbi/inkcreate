require "test_helper"

class DispatchDueRemindersJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

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

  test "marks a due reminder triggered and delivers one push payload per enabled device" do
    user = build_user(email: "dispatch-reminder@example.com")
    enabled_device = user.devices.create!(
      user_agent: "Chrome",
      push_enabled: true,
      push_endpoint: "https://example.test/push/enabled",
      push_p256dh_key: "key-1",
      push_auth_key: "auth-1",
      last_seen_at: Time.current
    )
    user.devices.create!(
      user_agent: "Safari",
      push_enabled: false,
      last_seen_at: Time.current
    )
    reminder = user.reminders.create!(
      title: "Standup follow-up",
      fire_at: 5.minutes.ago
    )
    deliveries = []

    clear_enqueued_jobs

    WebPushDeliverer.stub(:configured?, true) do
      WebPushDeliverer.stub(:deliver, ->(device:, payload:) { deliveries << { device: device, payload: payload } }) do
        DispatchDueRemindersJob.perform_now(reminder.id)
      end
    end

    reminder.reload
    assert reminder.status_triggered?
    assert_not_nil reminder.last_triggered_at
    assert_equal 1, deliveries.size
    assert_equal enabled_device.id, deliveries.first[:device].id
    assert_equal reminder.title, deliveries.first[:payload][:title]
  end
end
