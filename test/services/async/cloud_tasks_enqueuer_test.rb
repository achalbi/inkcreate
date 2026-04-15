require "test_helper"

class Async::CloudTasksEnqueuerTest < ActiveSupport::TestCase
  FakeClient = Class.new do
    class << self
      attr_accessor :captured_parent, :captured_task
    end

    def queue_path(project:, location:, queue:)
      "projects/#{project}/locations/#{location}/queues/#{queue}"
    end

    def create_task(parent:, task:)
      self.class.captured_parent = parent
      self.class.captured_task = task
    end
  end

  def with_cloud_tasks_env(overrides)
    keys = overrides.keys
    previous = keys.index_with { |key| ENV[key] }

    overrides.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end

    yield
  ensure
    previous.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
  end

  setup do
    FakeClient.captured_parent = nil
    FakeClient.captured_task = nil
  end

  test "uses internal task token in token mode even when a cloud tasks service account is present" do
    with_cloud_tasks_env(
      "GCP_PROJECT_ID" => "thoughtbasics",
      "GCP_REGION" => "us-central1",
      "WORKER_BASE_URL" => "https://inkcreate-git.example.run.app",
      "INTERNAL_TASK_TOKEN" => "shared-secret",
      "CLOUD_TASKS_SERVICE_ACCOUNT_EMAIL" => "inkcreate-tasks-invoker@thoughtbasics.iam.gserviceaccount.com",
      "CLOUD_TASKS_AUTH_MODE" => "token"
    ) do
      Async::CloudTasksEnqueuer.stub(:client_class, FakeClient) do
        Async::CloudTasksEnqueuer.stub(:post_http_method, :post) do
          Async::CloudTasksEnqueuer.new.enqueue(queue: "drive-sync-jobs", path: "/internal/google_drive_exports/export-123/perform")
        end
      end
    end

    request = FakeClient.captured_task.fetch(:http_request)

    assert_equal "projects/thoughtbasics/locations/us-central1/queues/drive-sync-jobs", FakeClient.captured_parent
    assert_equal "shared-secret", request.fetch(:headers).fetch("X-Internal-Task-Token")
    assert_not request.key?(:oidc_token)
  end

  test "uses oidc token in oidc mode" do
    with_cloud_tasks_env(
      "GCP_PROJECT_ID" => "thoughtbasics",
      "GCP_REGION" => "us-central1",
      "WORKER_BASE_URL" => "https://inkcreate-worker.example.run.app",
      "INTERNAL_TASK_TOKEN" => "shared-secret",
      "CLOUD_TASKS_SERVICE_ACCOUNT_EMAIL" => "inkcreate-tasks-invoker@thoughtbasics.iam.gserviceaccount.com",
      "CLOUD_TASKS_AUTH_MODE" => "oidc"
    ) do
      Async::CloudTasksEnqueuer.stub(:client_class, FakeClient) do
        Async::CloudTasksEnqueuer.stub(:post_http_method, :post) do
          Async::CloudTasksEnqueuer.new.enqueue(queue: "drive-sync-jobs", path: "/internal/google_drive_exports/export-123/perform")
        end
      end
    end

    request = FakeClient.captured_task.fetch(:http_request)

    assert_equal(
      {
        service_account_email: "inkcreate-tasks-invoker@thoughtbasics.iam.gserviceaccount.com",
        audience: "https://inkcreate-worker.example.run.app"
      },
      request[:oidc_token]
    )
    assert_not request.fetch(:headers).key?("X-Internal-Task-Token")
  end

  test "raises a configuration error when no auth strategy is configured" do
    error = assert_raises(Async::CloudTasksEnqueuer::ConfigurationError) do
      with_cloud_tasks_env(
        "GCP_PROJECT_ID" => "thoughtbasics",
        "GCP_REGION" => "us-central1",
        "WORKER_BASE_URL" => "https://inkcreate-git.example.run.app",
        "INTERNAL_TASK_TOKEN" => nil,
        "CLOUD_TASKS_SERVICE_ACCOUNT_EMAIL" => nil,
        "CLOUD_TASKS_AUTH_MODE" => "token"
      ) do
        Async::CloudTasksEnqueuer.stub(:client_class, FakeClient) do
          Async::CloudTasksEnqueuer.stub(:post_http_method, :post) do
            Async::CloudTasksEnqueuer.new.enqueue(queue: "drive-sync-jobs", path: "/internal/google_drive_exports/export-123/perform")
          end
        end
      end
    end

    assert_match(/Cloud Tasks auth is misconfigured/, error.message)
  end
end
