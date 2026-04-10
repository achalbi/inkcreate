require "json"
require "net/http"

module Auth
  class GoogleOauthClient
    AUTHORIZATION_URI = "https://accounts.google.com/o/oauth2/v2/auth".freeze
    TOKEN_CREDENTIAL_URI = "https://oauth2.googleapis.com/token".freeze
    USER_INFO_URI = URI("https://openidconnect.googleapis.com/v1/userinfo")
    SCOPE = "openid email profile".freeze
    GENERIC_ERROR_MESSAGE = "Google sign-in could not be completed. Please try again.".freeze

    class Error < StandardError; end

    def self.configured?
      ENV["GOOGLE_OAUTH_CLIENT_ID"].present? &&
        ENV["GOOGLE_OAUTH_CLIENT_SECRET"].present?
    end

    def authorization_url(state:, redirect_uri:)
      uri = URI(AUTHORIZATION_URI)
      uri.query = URI.encode_www_form(
        client_id: ENV.fetch("GOOGLE_OAUTH_CLIENT_ID"),
        redirect_uri: redirect_uri,
        response_type: "code",
        scope: SCOPE,
        state: state,
        access_type: "online",
        include_granted_scopes: "true",
        prompt: "select_account"
      )
      uri.to_s
    end

    def exchange_code!(code:, redirect_uri:)
      client = oauth_client(redirect_uri: redirect_uri)
      client.code = code
      client.fetch_access_token!
    rescue StandardError => error
      raise Error, GENERIC_ERROR_MESSAGE if oauth_exchange_error?(error)

      raise
    end

    def fetch_profile!(access_token:)
      request = Net::HTTP::Get.new(USER_INFO_URI)
      request["Authorization"] = "Bearer #{access_token}"

      response = Net::HTTP.start(USER_INFO_URI.host, USER_INFO_URI.port, use_ssl: true) do |http|
        http.request(request)
      end

      raise Error, GENERIC_ERROR_MESSAGE unless response.is_a?(Net::HTTPSuccess)

      profile = JSON.parse(response.body)
      email = profile["email"].to_s.strip
      email_verified = ActiveModel::Type::Boolean.new.cast(profile["email_verified"])

      raise Error, "Google account did not provide a verified email address." unless email.present? && email_verified

      profile
    rescue JSON::ParserError
      raise Error, GENERIC_ERROR_MESSAGE
    end

    private

    def oauth_client(redirect_uri:)
      Signet::OAuth2::Client.new(
        authorization_uri: AUTHORIZATION_URI,
        token_credential_uri: TOKEN_CREDENTIAL_URI,
        client_id: ENV.fetch("GOOGLE_OAUTH_CLIENT_ID"),
        client_secret: ENV.fetch("GOOGLE_OAUTH_CLIENT_SECRET"),
        redirect_uri: redirect_uri,
        scope: SCOPE
      )
    end

    def oauth_exchange_error?(error)
      defined?(Signet::AuthorizationError) && error.is_a?(Signet::AuthorizationError)
    end
  end
end
