module CurrentUserContext
  private

  def current_user
    @current_user ||= begin
      session_user = session[:browser_user_id].present? ? User.find_by(id: session[:browser_user_id]) : nil
      warden_user = request.env["warden"]&.user(:user)

      session_user || (warden_user if warden_user.is_a?(User))
    end
  end

  def user_signed_in?
    current_user.present?
  end
end
