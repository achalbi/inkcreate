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
    def failing_enqueuer.enqueue(queue:, path:)
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
end
