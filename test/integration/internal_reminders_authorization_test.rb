require "test_helper"

class InternalRemindersAuthorizationTest < ActionDispatch::IntegrationTest
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

  def build_reminder
    user = build_user(email: "internal-reminder-auth-#{SecureRandom.hex(4)}@example.com")

    user.reminders.create!(
      title: "Follow up",
      fire_at: 10.minutes.from_now
    )
  end

  test "rejects spoofed cloud tasks header when internal task token is configured" do
    previous_token = ENV["INTERNAL_TASK_TOKEN"]
    ENV["INTERNAL_TASK_TOKEN"] = "shared-secret"
    reminder = build_reminder

    post "/internal/reminders/#{reminder.id}/perform", headers: {
      "X-Cloudtasks-Taskname" => "spoofed"
    }

    assert_response :unauthorized
  ensure
    ENV["INTERNAL_TASK_TOKEN"] = previous_token
  end

  test "accepts request with internal task token when configured" do
    previous_token = ENV["INTERNAL_TASK_TOKEN"]
    ENV["INTERNAL_TASK_TOKEN"] = "shared-secret"
    reminder = build_reminder
    dispatched_ids = []

    DispatchDueRemindersJob.stub(:perform_now, ->(id) { dispatched_ids << id }) do
      post "/internal/reminders/#{reminder.id}/perform", headers: {
        "X-Internal-Task-Token" => "shared-secret"
      }
    end

    assert_response :accepted
    assert_equal [ reminder.id ], dispatched_ids
  ensure
    ENV["INTERNAL_TASK_TOKEN"] = previous_token
  end

  test "accepts cloud tasks header when worker header auth is enabled" do
    previous_token = ENV["INTERNAL_TASK_TOKEN"]
    previous_header_auth = ENV["CLOUD_TASKS_HEADER_AUTH_ENABLED"]
    ENV["INTERNAL_TASK_TOKEN"] = nil
    ENV["CLOUD_TASKS_HEADER_AUTH_ENABLED"] = "true"
    reminder = build_reminder
    dispatched_ids = []

    DispatchDueRemindersJob.stub(:perform_now, ->(id) { dispatched_ids << id }) do
      post "/internal/reminders/#{reminder.id}/perform", headers: {
        "X-Cloudtasks-Taskname" => "real-task"
      }
    end

    assert_response :accepted
    assert_equal [ reminder.id ], dispatched_ids
  ensure
    ENV["INTERNAL_TASK_TOKEN"] = previous_token
    ENV["CLOUD_TASKS_HEADER_AUTH_ENABLED"] = previous_header_auth
  end
end
