module Drive
  class OauthClient
    SCOPE = "https://www.googleapis.com/auth/drive.file".freeze

    def authorization_url(state:)
      oauth_client.update!(
        state: state,
        access_type: "offline",
        prompt: "consent",
        include_granted_scopes: true
      )
      oauth_client.authorization_uri.to_s
    end

    def exchange_code!(code:)
      oauth_client.code = code
      oauth_client.fetch_access_token!
    end

    private

    def oauth_client
      @oauth_client ||= Signet::OAuth2::Client.new(
        authorization_uri: "https://accounts.google.com/o/oauth2/auth",
        token_credential_uri: "https://oauth2.googleapis.com/token",
        client_id: ENV.fetch("GOOGLE_OAUTH_CLIENT_ID"),
        client_secret: ENV.fetch("GOOGLE_OAUTH_CLIENT_SECRET"),
        redirect_uri: ENV.fetch("GOOGLE_DRIVE_REDIRECT_URI"),
        scope: SCOPE
      )
    end
  end
end
