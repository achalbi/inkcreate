module Async
  class CloudTasksEnqueuer
    class ConfigurationError < StandardError; end

    class << self
      def client_class
        require "google/cloud/tasks/v2"
        Google::Cloud::Tasks::V2::CloudTasks::Client
      end

      def post_http_method
        require "google/cloud/tasks/v2"
        Google::Cloud::Tasks::V2::HttpMethod::POST
      end
    end

    def enqueue(queue:, path:, schedule_at: nil)
      task = {
        http_request: http_request(path)
      }
      task[:schedule_time] = schedule_time(schedule_at) if schedule_at.present?

      client.create_task(
        parent: queue_path(queue),
        task: task
      )
    end

    private

    def client
      @client ||= self.class.client_class.new
    end

    def queue_path(queue)
      client.queue_path(
        project: ENV.fetch("GCP_PROJECT_ID"),
        location: ENV.fetch("GCP_REGION"),
        queue: queue
      )
    end

    def http_request(path)
      request = {
        http_method: self.class.post_http_method,
        url: "#{ENV.fetch('WORKER_BASE_URL')}#{path}",
        headers: {
          "Content-Type" => "application/json"
        },
        body: "{}"
      }

      if use_oidc_token?
        request[:oidc_token] = {
          service_account_email: ENV.fetch("CLOUD_TASKS_SERVICE_ACCOUNT_EMAIL"),
          audience: ENV.fetch("WORKER_BASE_URL")
        }
      elsif ENV["INTERNAL_TASK_TOKEN"].present?
        request[:headers]["X-Internal-Task-Token"] = ENV.fetch("INTERNAL_TASK_TOKEN")
      else
        raise ConfigurationError, configuration_error_message
      end

      request
    end

    def use_oidc_token?
      cloud_tasks_auth_mode == "oidc"
    end

    def cloud_tasks_auth_mode
      ENV.fetch("CLOUD_TASKS_AUTH_MODE", "token")
    end

    def configuration_error_message
      "Cloud Tasks auth is misconfigured. Configure CLOUD_TASKS_AUTH_MODE=token with INTERNAL_TASK_TOKEN " \
        "for single-service mode, or CLOUD_TASKS_AUTH_MODE=oidc with CLOUD_TASKS_SERVICE_ACCOUNT_EMAIL for worker mode."
    end

    def schedule_time(schedule_at)
      return if schedule_at.blank?

      timestamp = Google::Protobuf::Timestamp.new
      timestamp.seconds = schedule_at.to_i
      timestamp.nanos = schedule_at.nsec
      timestamp
    end
  end
end
