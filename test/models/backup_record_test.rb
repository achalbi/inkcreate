require "test_helper"

class BackupRecordTest < ActiveSupport::TestCase
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

  def build_capture(user:, title:)
    user.captures.create!(
      title: title,
      original_filename: "#{title.parameterize}.jpg",
      content_type: "image/jpeg",
      byte_size: 1024,
      storage_bucket: "test-bucket",
      storage_object_key: "users/#{user.id}/uploads/test/#{title.parameterize}.jpg",
      page_type: "blank",
      backup_status: :local_only
    )
  end

  test "latest_per_capture_provider returns the newest record per capture and provider" do
    user = build_user(email: "backup-record-scope@example.com")
    first_capture = build_capture(user: user, title: "First")
    second_capture = build_capture(user: user, title: "Second")

    older_record = first_capture.backup_records.create!(
      user: user,
      provider: "google_drive",
      status: :uploaded,
      remote_path: "Captures / First / older"
    )
    older_record.update_column(:updated_at, 2.days.ago)

    newer_record = first_capture.backup_records.create!(
      user: user,
      provider: "google_drive",
      status: :uploaded,
      remote_path: "Captures / First / newer"
    )
    newer_record.update_column(:updated_at, 1.day.ago)

    second_record = second_capture.backup_records.create!(
      user: user,
      provider: "google_drive",
      status: :uploaded,
      remote_path: "Captures / Second"
    )

    records = BackupRecord.where(user: user).latest_per_capture_provider.recent_first.to_a

    assert_equal [second_record.id, newer_record.id], records.map(&:id)
    assert_not_includes records.map(&:id), older_record.id
  end
end
