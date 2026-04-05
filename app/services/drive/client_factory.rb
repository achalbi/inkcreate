module Drive
  class ClientFactory
    def self.build(user:)
      raise ArgumentError, "Google Drive is not connected" unless user.google_drive_connected?

      credentials = Google::Auth::UserRefreshCredentials.new(
        client_id: ENV.fetch("GOOGLE_OAUTH_CLIENT_ID"),
        client_secret: ENV.fetch("GOOGLE_OAUTH_CLIENT_SECRET"),
        scope: ["https://www.googleapis.com/auth/drive.file"],
        access_token: user.google_drive_access_token,
        refresh_token: user.google_drive_refresh_token
      )

      service = Google::Apis::DriveV3::DriveService.new
      service.authorization = credentials
      service
    end
  end
end
