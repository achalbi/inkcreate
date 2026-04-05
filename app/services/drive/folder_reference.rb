require "uri"

module Drive
  class FolderReference
    FOLDER_PATH_PATTERN = %r{/folders/([A-Za-z0-9_-]+)}.freeze
    ID_PATTERN = /\A[A-Za-z0-9_-]{10,}\z/.freeze

    def self.extract(value)
      new(value).extract
    end

    def initialize(value)
      @value = value.to_s.strip
    end

    def extract
      return if value.blank?
      return value if value == "root"
      return value if value.match?(ID_PATTERN)

      extract_from_url
    end

    private

    attr_reader :value

    def extract_from_url
      uri = URI.parse(value)

      if (match = uri.path.to_s.match(FOLDER_PATH_PATTERN))
        return match[1]
      end

      Rack::Utils.parse_query(uri.query).fetch("id", nil).presence
    rescue URI::InvalidURIError
      nil
    end
  end
end
