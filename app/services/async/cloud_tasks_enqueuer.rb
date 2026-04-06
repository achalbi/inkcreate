module Async
  class CloudTasksEnqueuer
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

    def enqueue(queue:, path:)
      client.create_task(
        parent: queue_path(queue),
        task: {
          http_request: http_request(path)
        }
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

      if ENV["CLOUD_TASKS_SERVICE_ACCOUNT_EMAIL"].present?
        request[:oidc_token] = {
          service_account_email: ENV.fetch("CLOUD_TASKS_SERVICE_ACCOUNT_EMAIL"),
          audience: ENV.fetch("WORKER_BASE_URL")
        }
      elsif ENV["INTERNAL_TASK_TOKEN"].present?
        request[:headers]["X-Internal-Task-Token"] = ENV.fetch("INTERNAL_TASK_TOKEN")
      end

      request
    end
  end
end
