module Internal
  class BaseController < ActionController::API
    before_action :set_current_context
    before_action :authorize_task_request!

    private

    def set_current_context
      Current.request_id = request.request_id
    end

    def authorize_task_request!
      expected_token = ENV["INTERNAL_TASK_TOKEN"].to_s
      provided_token = request.headers["X-Internal-Task-Token"].to_s

      # When a shared task token is configured, require it explicitly because
      # this deployment currently routes task callbacks through the public app
      # service URL.
      return if expected_token.present? && ActiveSupport::SecurityUtils.secure_compare(provided_token, expected_token)

      # In split-service mode the private worker can rely on Cloud Run's
      # platform auth and accept genuine Cloud Tasks callbacks directly.
      return if cloud_tasks_header_auth_enabled? && request.headers["X-Cloudtasks-Taskname"].present?

      head :unauthorized
    end

    def cloud_tasks_header_auth_enabled?
      ActiveModel::Type::Boolean.new.cast(ENV.fetch("CLOUD_TASKS_HEADER_AUTH_ENABLED", "false"))
    end
  end
end
