module Drive
  class ErrorMessage
    API_DISABLED_PATTERNS = [
      /Google Drive API has not been used in project/i,
      /accessNotConfigured/i,
      /SERVICE_DISABLED/i,
      %r{drive\.googleapis\.com/overview\?project=}i
    ].freeze

    API_DISABLED_MESSAGE = "Google Drive API is not enabled for this deployment yet. Enable the Google Drive API in the Google Cloud project, wait a few minutes, and try again.".freeze
    FALLBACK_MESSAGE = "Google Drive request failed. Please try again.".freeze

    def self.for(error)
      message = error&.message.to_s

      return message if error.is_a?(Drive::ClientFactory::AuthorizationRequiredError)
      return API_DISABLED_MESSAGE if api_disabled?(message)
      return FALLBACK_MESSAGE if message.blank?

      message
    end

    def self.api_disabled?(message)
      API_DISABLED_PATTERNS.any? { |pattern| pattern.match?(message) }
    end
  end
end
