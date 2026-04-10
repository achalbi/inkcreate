require "test_helper"
require "active_job/test_helper"
require "securerandom"

class GoogleDriveExportJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  test "re-enqueues with backoff when the export record is missing" do
    GoogleDriveExportJob.perform_now(SecureRandom.uuid)

    assert_equal 1, enqueued_jobs.size
    assert_equal GoogleDriveExportJob, enqueued_jobs.first[:job]
    assert_operator enqueued_jobs.first[:at], :>, Time.current.to_f
  end
end
