module Api
  module V1
    module Auth
      class CsrfTokensController < ApplicationController
        def show
          render json: {
            csrf_token: form_authenticity_token,
            authenticated: user_signed_in?,
            user: user_signed_in? ? UserSerializer.new(current_user).as_json : nil
          }
        end
      end
    end
  end
end
