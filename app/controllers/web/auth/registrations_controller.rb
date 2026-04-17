module Web
  module Auth
    class RegistrationsController < BrowserController
      before_action :redirect_signed_in_user, only: :new

      def new
        return redirect_to(browser_sign_in_path) if google_only_auth_mode?

        @user = User.new
      end

      def create
        unless password_auth_available?
          @user = User.new
          flash.now[:alert] = "Email and password sign-up is disabled. Continue with Google instead."
          return render "web/auth/sessions/new", status: :unprocessable_entity
        end

        @user = User.new(registration_params)
        @user.assign_attributes(time_zone: effective_time_zone_name, locale: "en")

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
        params.require(:user).permit(:email, :password, :password_confirmation)
      end
    end
  end
end
