module Web
  module Auth
    class SessionsController < BrowserController
      before_action :redirect_signed_in_user, only: :new

      def new; end

      def create
        user = User.find_for_authentication(email: session_params.fetch(:email))

        unless user&.valid_password?(session_params.fetch(:password))
          flash.now[:alert] = "Invalid email or password."
          return render :new, status: :unprocessable_entity
        end

        sign_in(:user, user)
        session[:browser_user_id] = user.id
        redirect_to post_auth_redirect_for(user), notice: "Welcome back."
      end

      def destroy
        session.delete(:browser_user_id)
        sign_out(:user) if current_user
        redirect_to root_path, notice: "Signed out."
      end

      private

      def redirect_signed_in_user
        redirect_to post_auth_redirect_for(current_user) if user_signed_in?
      end

      def session_params
        params.require(:user).permit(:email, :password)
      end
    end
  end
end
