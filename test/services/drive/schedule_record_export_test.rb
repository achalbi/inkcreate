require "test_helper"

class Drive::ScheduleRecordExportTest < ActiveSupport::TestCase
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

  def build_entry(email:)
    user = build_user(email: email)
    entry = user.notepad_entries.create!(
      entry_date: Date.new(2026, 4, 6),
      title: "",
      notes: "Ready for export"
    )

    [user, entry]
  end

  test "logs a skip when drive is not connected" do
    user, entry = build_entry(email: "schedule-record-export-skip@example.com")
    user.ensure_app_setting!.update!(backup_enabled: true, backup_provider: "google_drive")
    events = []

    Observability::EventLogger.stub :info, ->(event:, payload:) { events << { event: event, payload: payload } } do
      assert_nil Drive::ScheduleRecordExport.new(record: entry).call
    end

    assert_equal "drive.record_export.skipped", events.last[:event]
    assert_equal "drive_not_connected", events.last[:payload][:reason]
    assert_equal entry.id, events.last[:payload][:record_id]
  end

  test "logs a skip when drive backup is disabled" do
    user, entry = build_entry(email: "schedule-record-export-disabled@example.com")
    user.update!(
      google_drive_refresh_token: "refresh-token",
      google_drive_connected_at: Time.current,
      google_drive_folder_id: "drive-folder-123"
    )
    events = []

    Observability::EventLogger.stub :info, ->(event:, payload:) { events << { event: event, payload: payload } } do
      assert_nil Drive::ScheduleRecordExport.new(record: entry).call
    end

    assert_equal "drive.record_export.skipped", events.last[:event]
    assert_equal "backup_disabled", events.last[:payload][:reason]
  end

  test "suppresses duplicate enqueue when export is already pending" do
    user, entry = build_entry(email: "schedule-record-export-pending@example.com")
    user.update!(
      google_drive_refresh_token: "refresh-token",
      google_drive_connected_at: Time.current,
      google_drive_folder_id: "drive-folder-456"
    )
    user.ensure_app_setting!.update!(backup_enabled: true, backup_provider: "google_drive")

    export = GoogleDriveExport.create!(
      user: user,
      exportable: entry,
      status: :pending,
      remote_photo_file_ids: {}
    )
    export.update_column(:updated_at, Time.current)

    enqueued = []
    events = []

    Async::Dispatcher.stub :enqueue_record_export, ->(id) { enqueued << id } do
      Observability::EventLogger.stub :info, ->(event:, payload:) { events << { event: event, payload: payload } } do
        returned_export = Drive::ScheduleRecordExport.new(record: entry).call

        assert_equal export, returned_export
      end
    end

    assert_empty enqueued
    assert_equal "drive.record_export.skipped", events.last[:event]
    assert_equal "already_pending", events.last[:payload][:reason]
  end
end
