module Web
  module Auth
    class RegistrationsController < BrowserController
      before_action :redirect_signed_in_user, only: :new

      def new
        @user = User.new(time_zone: "UTC", locale: "en")
      end

      def create
        @user = User.new(registration_params)

        if @user.save
          sign_in(:user, @user)
          session[:browser_user_id] = @user.id
          redirect_to post_auth_redirect_for(@user), notice: @user.admin? ? "Admin account created." : "Account created."
        else
          flash.now[:alert] = @user.errors.full_messages.to_sentence
          render :new, status: :unprocessable_entity
        end
      end

      private

      def redirect_signed_in_user
        redirect_to post_auth_redirect_for(current_user) if user_signed_in?
      end

      def registration_params
        params.require(:user).permit(:email, :password, :password_confirmation, :time_zone, :locale)
      end
    end
  end
end
