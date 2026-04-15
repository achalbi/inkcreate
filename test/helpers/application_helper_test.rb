require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  include ActiveSupport::Testing::TimeHelpers

  test "defaults fresh reminders to one hour from now" do
    Time.use_zone("UTC") do
      travel_to Time.zone.local(2026, 4, 15, 10, 30, 45) do
        assert_equal "2026-04-15T11:30", reminder_fire_at_local_value(Reminder.new)
      end
    end
  end

  test "does not overwrite blank reminders with validation errors" do
    reminder = Reminder.new
    reminder.errors.add(:fire_at, "can't be blank")

    assert_nil reminder_fire_at_local_value(reminder)
  end
end
