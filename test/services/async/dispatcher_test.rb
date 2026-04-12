require "test_helper"
require "active_job/test_helper"

class Async::DispatcherTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  test "falls back to active job enqueue when cloud tasks client cannot load" do
    previous_backend = ENV["JOB_BACKEND"]
    ENV["JOB_BACKEND"] = "cloud_tasks"

    failing_enqueuer = Object.new
    def failing_enqueuer.enqueue(queue:, path:, schedule_at: nil)
      raise NameError, "uninitialized constant Google::Cloud::Tasks::V2"
    end

    Async::CloudTasksEnqueuer.stub(:new, failing_enqueuer) do
      assert_enqueued_with(job: GoogleDriveExportJob, args: [123]) do
        Async::Dispatcher.enqueue_record_export(123)
      end
    end
  ensure
    ENV["JOB_BACKEND"] = previous_backend
  end

  test "enqueues reminder callbacks into the dedicated reminder queue with schedule time" do
    previous_backend = ENV["JOB_BACKEND"]
    previous_queue = ENV["CLOUD_TASKS_REMINDERS_QUEUE"]
    ENV["JOB_BACKEND"] = "cloud_tasks"
    ENV["CLOUD_TASKS_REMINDERS_QUEUE"] = "reminder-jobs-test"
    fire_at = 15.minutes.from_now.change(usec: 0)
    captured = nil

    capturing_enqueuer = Object.new
    capturing_enqueuer.define_singleton_method(:enqueue) do |queue:, path:, schedule_at: nil|
      captured = { queue: queue, path: path, schedule_at: schedule_at }
    end

    Async::CloudTasksEnqueuer.stub(:new, capturing_enqueuer) do
      Async::Dispatcher.enqueue_reminder("reminder-123", fire_at: fire_at)
    end

    assert_equal "reminder-jobs-test", captured[:queue]
    assert_equal "/internal/reminders/reminder-123/perform", captured[:path]
    assert_equal fire_at.to_i, captured[:schedule_at].to_i
  ensure
    ENV["JOB_BACKEND"] = previous_backend
    ENV["CLOUD_TASKS_REMINDERS_QUEUE"] = previous_queue
  end
end
