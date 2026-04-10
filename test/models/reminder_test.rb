require "test_helper"

class ReminderTest < ActiveSupport::TestCase
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

  test "requires a title and fire time" do
    reminder = Reminder.new

    assert_not reminder.valid?
    assert_includes reminder.errors.full_messages, "Title can't be blank"
    assert_includes reminder.errors.full_messages, "Fire at can't be blank"
  end

  test "standalone reminder points to its edit page" do
    user = build_user(email: "standalone-reminder@example.com")
    reminder = user.reminders.create!(
      title: "Call client",
      fire_at: 15.minutes.from_now
    )

    assert reminder.standalone?
    assert_equal Rails.application.routes.url_helpers.edit_reminder_path(reminder), reminder.destination_path
  end

  test "scopes sort upcoming reminders nearest first and history most recent first" do
    user = build_user(email: "sorted-reminders@example.com")

    later_upcoming = user.reminders.create!(title: "Later upcoming", fire_at: 2.days.from_now)
    sooner_upcoming = user.reminders.create!(title: "Sooner upcoming", fire_at: 3.hours.from_now)
    overdue_pending = user.reminders.create!(title: "Overdue pending", fire_at: 15.minutes.ago)
    older_history = user.reminders.create!(
      title: "Older history",
      fire_at: 3.days.ago,
      status: :triggered,
      last_triggered_at: 2.days.ago
    )
    newer_history = user.reminders.create!(
      title: "Newer history",
      fire_at: 2.days.ago,
      status: :dismissed,
      last_triggered_at: 1.day.ago
    )

    assert_equal [sooner_upcoming, later_upcoming], user.reminders.upcoming_first.to_a
    assert_equal [overdue_pending, newer_history, older_history], user.reminders.history_recent_first.to_a
  end

  test "history includes expired reminders" do
    user = build_user(email: "expired-reminders@example.com")
    expired_reminder = user.reminders.create!(
      title: "Expired reminder",
      fire_at: 1.hour.ago,
      status: :expired
    )

    assert_includes user.reminders.history.to_a, expired_reminder
  end
end
