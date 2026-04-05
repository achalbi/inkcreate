require "test_helper"

class NotepadEntryTest < ActiveSupport::TestCase
  test "requires title or notes" do
    user = User.create!(
      email: "notes@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )

    entry = user.notepad_entries.new(entry_date: Date.current)

    assert_not entry.valid?
    assert_includes entry.errors.full_messages, "Add a title or notes for this entry."
  end
end
