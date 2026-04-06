module Drive
  class ClientFactory
    REFRESH_WINDOW_SECONDS = 60

    class AuthorizationRequiredError < StandardError; end

    def self.build(user:)
      raise ArgumentError, "Google Drive is not connected" unless user.google_drive_connected?

      credentials = Google::Auth::UserRefreshCredentials.new(
        client_id: ENV.fetch("GOOGLE_OAUTH_CLIENT_ID"),
        client_secret: ENV.fetch("GOOGLE_OAUTH_CLIENT_SECRET"),
        scope: [Drive::OauthClient::SCOPE],
        access_token: user.google_drive_access_token,
        refresh_token: user.google_drive_refresh_token,
        expires_at: user.google_drive_token_expires_at
      )

      refresh_credentials!(user: user, credentials: credentials) if user.google_drive_access_token.blank? || user.google_drive_token_expires_at.blank? || credentials.expires_within?(REFRESH_WINDOW_SECONDS)

      service = Google::Apis::DriveV3::DriveService.new
      service.authorization = credentials
      service
    rescue Google::Apis::AuthorizationError, Google::Auth::AuthorizationError, Signet::AuthorizationError
      raise AuthorizationRequiredError, "Google Drive authorization expired. Reconnect Google Drive and try again."
    end

    def self.refresh_credentials!(user:, credentials:)
      credentials.refresh!

      attributes = {
        google_drive_access_token: credentials.access_token,
        google_drive_token_expires_at: credentials.expires_at
      }
      attributes[:google_drive_refresh_token] = credentials.refresh_token if credentials.refresh_token.present?

      user.update!(attributes)
    end
  end
end
