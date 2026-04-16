module Api
  module V1
    module Auth
      class SessionsController < ApplicationController
        include SafePasswordAuthentication
        def create
          user = User.find_for_authentication(email: session_params.fetch(:email))

          unless password_matches?(user, session_params.fetch(:password))
            return render json: { error: "Invalid email or password" }, status: :unauthorized
          end

          sign_in(:user, user)
          session[:browser_user_id] = user.id
          render json: { user: UserSerializer.new(user).as_json }
        end

        def destroy
          session.delete(:browser_user_id)
          sign_out(:user) if current_user
          head :no_content
        end

        private

        def session_params
          params.require(:user).permit(:email, :password)
        end

        def render_invalid_credentials
          render json: { error: "Invalid email or password" }, status: :unauthorized
        end
      end
    end
  end
end
