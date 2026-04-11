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

  def build_todo_item(email:, content: "Follow up")
    user = build_user(email: email)
    notebook = user.notebooks.create!(title: "Launch board", status: :active)
    chapter = notebook.chapters.create!(title: "Prep")
    page = chapter.pages.create!(title: "Checklist", notes: "Tasks for launch")
    todo_list = page.create_todo_list!(enabled: true, hide_completed: false)

    [user, todo_list.todo_items.create!(content: content)]
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

  test "allows only one reminder per todo item" do
    user, todo_item = build_todo_item(email: "todo-item-reminder@example.com")

    user.reminders.create!(
      title: "First reminder",
      fire_at: 1.hour.from_now,
      target: todo_item
    )

    duplicate = user.reminders.new(
      title: "Second reminder",
      fire_at: 2.hours.from_now,
      target: todo_item
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors.full_messages, "This to-do item already has a reminder."
  end

  test "rescheduling a triggered reminder rearms it" do
    user, todo_item = build_todo_item(email: "rearm-reminder@example.com")
    reminder = user.reminders.create!(
      title: "Check in",
      fire_at: 30.minutes.from_now,
      status: :triggered,
      last_triggered_at: 5.minutes.ago,
      target: todo_item
    )

    new_fire_at = 2.hours.from_now.change(sec: 0)
    reminder.update!(fire_at: new_fire_at)

    assert_equal "pending", reminder.reload.status
    assert_equal new_fire_at.to_i, reminder.fire_at.to_i
    assert_nil reminder.snooze_until
    assert_nil reminder.last_triggered_at
  end
end
