module Api
  module V1
    class DriveConnectionsController < BaseController
      def show
        render json: {
          connected: current_user.google_drive_connected?,
          folder_id: current_user.google_drive_folder_id,
          connected_at: current_user.google_drive_connected_at
        }
      end

      def create
        state = SecureRandom.hex(24)
        session[:drive_oauth_state] = state

        render json: {
          authorization_url: Drive::OauthClient.new.authorization_url(state: state)
        }, status: :created
      end

      def callback
        return_to = session.delete(:drive_oauth_return_to)
        expected_state = session.delete(:drive_oauth_state).to_s

        if params[:error].present?
          return handle_browser_callback_error(return_to, "Google Drive connection was canceled.")
        end

        unless expected_state.present? &&
               params[:state].present? &&
               ActiveSupport::SecurityUtils.secure_compare(expected_state, params[:state].to_s)
          return handle_browser_callback_error(return_to, "Google Drive connection could not be verified.")
        end

        token_payload = Drive::OauthClient.new.exchange_code!(code: params.fetch(:code))
        current_user.update!(
          google_drive_access_token: token_payload["access_token"],
          google_drive_refresh_token: token_payload["refresh_token"].presence || current_user.google_drive_refresh_token,
          google_drive_token_expires_at: Time.current + token_payload.fetch("expires_in", 3600).to_i.seconds,
          google_drive_connected_at: Time.current
        )

        if return_to.present?
          session[:browser_notice] = "Google Drive connected. Create or choose a backup folder to finish setup."
          redirect_to return_to
        else
          render json: { connected: true }
        end
      rescue StandardError => error
        return handle_browser_callback_error(return_to, error.message) if return_to.present?

        raise
      end

      def update
        current_user.update!(google_drive_folder_id: drive_connection_params.fetch(:google_drive_folder_id))
        render json: { connected: true, folder_id: current_user.google_drive_folder_id }
      end

      def destroy
        current_user.update!(
          google_drive_access_token: nil,
          google_drive_refresh_token: nil,
          google_drive_token_expires_at: nil,
          google_drive_connected_at: nil,
          google_drive_folder_id: nil
        )

        head :no_content
      end

      private

      def drive_connection_params
        params.require(:drive_connection).permit(:google_drive_folder_id)
      end

      def handle_browser_callback_error(return_to, message)
        session[:browser_alert] = message
        redirect_to(return_to.presence || settings_backup_path)
      end
    end
  end
end
