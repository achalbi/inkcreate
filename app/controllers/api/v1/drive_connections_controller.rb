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
        popup_flow = ActiveModel::Type::Boolean.new.cast(session.delete(:drive_oauth_popup))
        expected_state = session.delete(:drive_oauth_state).to_s

        if params[:error].present?
          return handle_browser_callback_error(return_to, "Google Drive connection was canceled.", popup: popup_flow)
        end

        unless expected_state.present? &&
               params[:state].present? &&
               ActiveSupport::SecurityUtils.secure_compare(expected_state, params[:state].to_s)
          return handle_browser_callback_error(return_to, "Google Drive connection could not be verified.", popup: popup_flow)
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
          popup_flow ? render_popup_callback(return_to) : redirect_to(return_to)
        else
          render json: { connected: true }
        end
      rescue StandardError => error
        return handle_browser_callback_error(return_to, error.message, popup: popup_flow) if return_to.present?

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

      def handle_browser_callback_error(return_to, message, popup: false)
        session[:browser_alert] = message
        target = return_to.presence || settings_backup_path
        popup ? render_popup_callback(target) : redirect_to(target)
      end

      def render_popup_callback(return_to)
        render html: <<~HTML.html_safe, layout: false
          <!DOCTYPE html>
          <html lang="en">
            <head>
              <meta charset="utf-8">
              <meta name="viewport" content="width=device-width,initial-scale=1">
              <title>Inkcreate Drive Connection</title>
            </head>
            <body>
              <script>
                (function() {
                  var payload = {
                    type: "inkcreate:drive-oauth",
                    returnTo: #{return_to.to_json}
                  };

                  try {
                    if (window.opener && !window.opener.closed) {
                      window.opener.postMessage(payload, #{request.base_url.to_json});
                    }
                  } catch (error) {
                    // Ignore cross-window messaging errors and fall back to redirect.
                  }

                  window.close();
                  window.location.replace(payload.returnTo);
                })();
              </script>
            </body>
          </html>
        HTML
      end
    end
  end
end
