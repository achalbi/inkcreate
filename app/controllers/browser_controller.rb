class BrowserController < ActionController::Base
  WORKSPACE_CONTROLLERS = %w[
    home
    notebooks
    chapters
    pages
    notepad_entries
    capture_studio
    inbox
    projects
    daily_logs
    captures
    search
    tasks
    library
    settings
    settings/backup
    settings/privacy
  ].freeze

  include ActionController::Cookies
  include ActionController::RequestForgeryProtection
  include ActiveStorage::SetCurrent
  include Devise::Controllers::Helpers
  include CurrentUserContext
  include RequestTimeZoneContext

  protect_from_forgery with: :exception
  layout :browser_layout

  helper_method :current_user, :user_signed_in?, :workspace_header_page?, :workspace_layout_page?, :versioned_public_asset_path
  before_action :set_request_context

  rescue_from ActiveRecord::RecordNotFound do
    head :not_found
  end

  private

  def set_request_context
    Current.request_id = request.request_id
    Current.user = current_user
    response.set_header("X-Request-Id", request.request_id)
  end

  def require_authenticated_user!
    redirect_to browser_sign_in_path, alert: "Sign in to continue." unless user_signed_in?
  end

  def require_admin!
    redirect_to dashboard_path, alert: "Admin access required." unless current_user&.admin?
  end

  def post_auth_redirect_for(user)
    user.admin? ? admin_dashboard_path : dashboard_path
  end

  def workspace_header_page?
    WORKSPACE_CONTROLLERS.include?(controller_path)
  end

  def workspace_layout_page?
    user_signed_in? && WORKSPACE_CONTROLLERS.include?(controller_path)
  end

  def browser_layout
    workspace_layout_page? ? "workspace" : "landing"
  end

  def versioned_public_asset_path(path)
    logical_path = path.to_s.delete_prefix("/")
    absolute_path = Rails.root.join("public", logical_path)

    return "/#{logical_path}" unless absolute_path.file?

    "/#{logical_path}?v=#{absolute_path.mtime.to_i}"
  end
end
