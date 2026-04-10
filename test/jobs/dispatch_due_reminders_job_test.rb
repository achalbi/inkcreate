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

  test "marks a due reminder triggered and enqueues one push job per enabled device" do
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

    clear_enqueued_jobs

    assert_enqueued_with(job: DeliverReminderPushJob, args: [reminder.id, enabled_device.id]) do
      DispatchDueRemindersJob.perform_now(reminder.id)
    end

    reminder.reload
    assert reminder.status_triggered?
    assert_not_nil reminder.last_triggered_at
  end
end
