module Drive
  class OauthClient
    SCOPE = "https://www.googleapis.com/auth/drive.file".freeze

    def self.configured?
      ENV["GOOGLE_OAUTH_CLIENT_ID"].present? &&
        ENV["GOOGLE_OAUTH_CLIENT_SECRET"].present? &&
        ENV["GOOGLE_DRIVE_REDIRECT_URI"].present?
    end

    def authorization_url(state:)
      uri = URI("https://accounts.google.com/o/oauth2/auth")
      uri.query = URI.encode_www_form(
        access_type: "offline",
        client_id: ENV.fetch("GOOGLE_OAUTH_CLIENT_ID"),
        include_granted_scopes: "true",
        prompt: "consent",
        redirect_uri: ENV.fetch("GOOGLE_DRIVE_REDIRECT_URI"),
        response_type: "code",
        scope: SCOPE,
        state: state
      )
      uri.to_s
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
