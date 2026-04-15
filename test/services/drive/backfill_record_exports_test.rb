require "test_helper"

class Drive::BackfillRecordExportsTest < ActiveSupport::TestCase
  def build_user(email:)
    user = User.create!(
      email: email,
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )
    user.update!(
      google_drive_refresh_token: "refresh-token",
      google_drive_connected_at: Time.current,
      google_drive_folder_id: "drive-folder-123"
    )
    user.ensure_app_setting!.update!(backup_enabled: true, backup_provider: "google_drive")
    user
  end

  test "counts only newly queued record exports" do
    user = build_user(email: "backfill-record-exports@example.com")
    pending_entry = user.notepad_entries.create!(
      entry_date: Date.new(2026, 4, 7),
      title: "Pending",
      notes: "Already queued"
    )
    fresh_entry = user.notepad_entries.create!(
      entry_date: Date.new(2026, 4, 8),
      title: "Fresh",
      notes: "Needs export"
    )
    GoogleDriveExport.create!(
      user: user,
      exportable: pending_entry,
      status: :pending,
      remote_photo_file_ids: {}
    )

    enqueued_ids = []

    Async::Dispatcher.stub(:enqueue_record_export, ->(id) { enqueued_ids << id }) do
      scheduled = Drive::BackfillRecordExports.new(user: user).call

      assert_equal 1, scheduled
    end

    assert_equal 1, enqueued_ids.size
    assert_equal fresh_entry.id, GoogleDriveExport.find(enqueued_ids.first).exportable_id
  end

  test "does not requeue an unchanged exported record" do
    user = build_user(email: "backfill-record-exports-unchanged@example.com")
    entry = user.notepad_entries.create!(
      entry_date: Date.new(2026, 4, 9),
      title: "Stable",
      notes: "Already exported"
    )
    export = GoogleDriveExport.create!(
      user: user,
      exportable: entry,
      status: :succeeded,
      exported_at: Time.current,
      remote_photo_file_ids: {}
    )
    export.update_column(:updated_at, Time.current)

    Async::Dispatcher.stub(:enqueue_record_export, ->(*) { flunk "should not enqueue unchanged export" }) do
      assert_equal 0, Drive::BackfillRecordExports.new(user: user).call
    end
  end
end
