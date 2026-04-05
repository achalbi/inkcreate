module Internal
  class BaseController < ActionController::API
    before_action :set_current_context
    before_action :authorize_task_request!

    private

    def set_current_context
      Current.request_id = request.request_id
    end

    def authorize_task_request!
      # In production, the Cloud Run worker service should require IAM auth and
      # receive Cloud Tasks OIDC-authenticated requests. The shared token path
      # is kept only as a simple local-development fallback.
      return if request.headers["X-Cloudtasks-Taskname"].present?

      expected_token = ENV["INTERNAL_TASK_TOKEN"].to_s
      provided_token = request.headers["X-Internal-Task-Token"].to_s

      return if expected_token.present? && ActiveSupport::SecurityUtils.secure_compare(provided_token, expected_token)

      head :unauthorized
    end
  end
end
