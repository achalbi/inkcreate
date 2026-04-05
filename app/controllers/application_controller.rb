class ApplicationController < ActionController::API
  include ActionController::Cookies
  include ActionController::RequestForgeryProtection
  include ActiveStorage::SetCurrent
  include Devise::Controllers::Helpers
  include CurrentUserContext

  protect_from_forgery with: :exception

  before_action :set_request_context
  after_action :set_csrf_cookie

  rescue_from ActiveRecord::RecordNotFound do |error|
    render json: { error: error.message }, status: :not_found
  end

  rescue_from ActiveRecord::RecordInvalid do |error|
    render json: { error: error.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  rescue_from ActionController::InvalidAuthenticityToken do
    render json: { error: "Invalid CSRF token" }, status: :unprocessable_entity
  end

  rescue_from ArgumentError do |error|
    render json: { error: error.message }, status: :unprocessable_entity
  end

  private

  def authenticate_user!
    return if user_signed_in?

    render json: { error: "Authentication required" }, status: :unauthorized
  end

  def set_request_context
    Current.request_id = request.request_id
    Current.user = current_user
    response.set_header("X-Request-Id", request.request_id)
  end

  def set_csrf_cookie
    cookies["CSRF-TOKEN"] = {
      value: form_authenticity_token,
      same_site: :lax,
      secure: Rails.env.production?
    }
  end
end
