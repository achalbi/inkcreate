module Web
  module Auth
    class GoogleController < BrowserController
      before_action :redirect_signed_in_user, only: :create

      def create
        return redirect_to(google_auth_return_path, alert: "Google sign-in is not configured for this app yet.") unless ::Auth::GoogleOauthClient.configured?

        state = SecureRandom.hex(24)
        session[:google_auth_state] = state
        session[:google_auth_return_to] = google_auth_return_path

        redirect_to google_oauth_client.authorization_url(
          state: state,
          redirect_uri: browser_google_auth_callback_url
        ), allow_other_host: true
      end

      def callback
        return_to = session.delete(:google_auth_return_to).presence || browser_sign_in_path
        expected_state = session.delete(:google_auth_state).to_s

        if params[:error].present?
          message = params[:error] == "access_denied" ? "Google sign-in was canceled." : "Google sign-in failed. Please try again."
          return redirect_to(return_to, alert: message)
        end

        unless oauth_state_verified?(expected_state)
          return redirect_to(return_to, alert: "Google sign-in could not be verified.")
        end

        token_payload = google_oauth_client.exchange_code!(
          code: params.fetch(:code),
          redirect_uri: browser_google_auth_callback_url
        )
        profile = google_oauth_client.fetch_profile!(access_token: token_payload.fetch("access_token"))
        user, created = find_or_create_google_user!(profile)

        sign_in(:user, user)
        session[:browser_user_id] = user.id

        notice = created ? "Account created with Google." : "Signed in with Google."
        redirect_to post_auth_redirect_for(user), notice: notice
      rescue ::Auth::GoogleOauthClient::Error => error
        redirect_to(return_to || browser_sign_in_path, alert: error.message)
      rescue KeyError
        redirect_to(return_to || browser_sign_in_path, alert: "Google sign-in failed. Please try again.")
      end

      private

      def google_oauth_client
        @google_oauth_client ||= ::Auth::GoogleOauthClient.new
      end

      def oauth_state_verified?(expected_state)
        expected_state.present? &&
          params[:state].present? &&
          ActiveSupport::SecurityUtils.secure_compare(expected_state, params[:state].to_s)
      end

      def find_or_create_google_user!(profile)
        email = profile.fetch("email").to_s.strip
        user = User.find_for_authentication(email: email)
        return [user, false] if user.present?

        password = Devise.friendly_token.first(32)
        user = User.create!(
          email: email,
          password: password,
          password_confirmation: password,
          time_zone: effective_time_zone_name,
          locale: "en"
        )

        [user, true]
      end

      def google_auth_return_path
        referer_path = URI.parse(request.referer.to_s).path if request.referer.present?
        [browser_sign_in_path, browser_sign_up_path].find { |path| path == referer_path } || browser_sign_in_path
      rescue URI::InvalidURIError
        browser_sign_in_path
      end

      def redirect_signed_in_user
        redirect_to post_auth_redirect_for(current_user) if user_signed_in?
      end
    end
  end
end
