require "test_helper"

class GoogleDriveExportTest < ActiveSupport::TestCase
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

  test "allows an empty remote photo file id map for pending exports" do
    user = build_user(email: "google-drive-export@example.com")
    entry = user.notepad_entries.create!(
      entry_date: Date.new(2026, 4, 6),
      title: "",
      notes: "Ready for export"
    )

    export = GoogleDriveExport.new(
      user: user,
      exportable: entry,
      status: :pending,
      remote_photo_file_ids: {}
    )

    assert export.valid?
  end

  test "requires remote photo file ids to stay a hash" do
    user = build_user(email: "google-drive-export-invalid@example.com")
    entry = user.notepad_entries.create!(
      entry_date: Date.new(2026, 4, 6),
      title: "",
      notes: "Ready for export"
    )

    export = GoogleDriveExport.new(
      user: user,
      exportable: entry,
      status: :pending,
      remote_photo_file_ids: "not-a-hash"
    )

    assert_not export.valid?
    assert_includes export.errors.full_messages, "Remote photo file ids must be a hash"
  end
end
