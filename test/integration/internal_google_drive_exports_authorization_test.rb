require "test_helper"

class InternalGoogleDriveExportsAuthorizationTest < ActionDispatch::IntegrationTest
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

  def build_export
    user = build_user(email: "internal-export-auth-#{SecureRandom.hex(4)}@example.com")
    entry = user.notepad_entries.create!(
      entry_date: Date.new(2026, 4, 6),
      title: "",
      notes: "Ready for internal export"
    )

    GoogleDriveExport.create!(
      user: user,
      exportable: entry,
      status: :pending,
      remote_photo_file_ids: {}
    )
  end

  test "rejects spoofed cloud tasks header when internal task token is configured" do
    previous_token = ENV["INTERNAL_TASK_TOKEN"]
    ENV["INTERNAL_TASK_TOKEN"] = "shared-secret"
    export = build_export

    post "/internal/google_drive_exports/#{export.id}/perform", headers: {
      "X-Cloudtasks-Taskname" => "spoofed"
    }

    assert_response :unauthorized
  ensure
    ENV["INTERNAL_TASK_TOKEN"] = previous_token
  end

  test "accepts request with internal task token when configured" do
    previous_token = ENV["INTERNAL_TASK_TOKEN"]
    ENV["INTERNAL_TASK_TOKEN"] = "shared-secret"
    export = build_export
    fake_exporter = Object.new
    def fake_exporter.call
      true
    end

    Drive::ExportRecord.stub(:new, fake_exporter) do
      post "/internal/google_drive_exports/#{export.id}/perform", headers: {
        "X-Internal-Task-Token" => "shared-secret"
      }
    end

    assert_response :accepted
  ensure
    ENV["INTERNAL_TASK_TOKEN"] = previous_token
  end

  test "accepts cloud tasks header when worker header auth is enabled" do
    previous_token = ENV["INTERNAL_TASK_TOKEN"]
    previous_header_auth = ENV["CLOUD_TASKS_HEADER_AUTH_ENABLED"]
    ENV["INTERNAL_TASK_TOKEN"] = nil
    ENV["CLOUD_TASKS_HEADER_AUTH_ENABLED"] = "true"
    export = build_export
    fake_exporter = Object.new
    def fake_exporter.call
      true
    end

    Drive::ExportRecord.stub(:new, fake_exporter) do
      post "/internal/google_drive_exports/#{export.id}/perform", headers: {
        "X-Cloudtasks-Taskname" => "real-task"
      }
    end

    assert_response :accepted
  ensure
    ENV["INTERNAL_TASK_TOKEN"] = previous_token
    ENV["CLOUD_TASKS_HEADER_AUTH_ENABLED"] = previous_header_auth
  end
end
