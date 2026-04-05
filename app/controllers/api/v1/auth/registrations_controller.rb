module Api
  module V1
    module Auth
      class RegistrationsController < ApplicationController
        def create
          user = User.create!(registration_params)
          sign_in(:user, user)
          session[:browser_user_id] = user.id

          render json: { user: UserSerializer.new(user).as_json }, status: :created
        end

        private

        def registration_params
          params.require(:user).permit(:email, :password, :password_confirmation, :time_zone, :locale)
        end
      end
    end
  end
end
