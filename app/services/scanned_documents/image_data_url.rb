require "base64"

module ScannedDocuments
  class ImageDataUrl
    def initialize(scanned_document:)
      @scanned_document = scanned_document
    end

    def call
      raise ArgumentError, "Scanned document image is missing" unless scanned_document.enhanced_image.attached?

      content_type = scanned_document.enhanced_image.blob.content_type.presence || "image/jpeg"
      encoded = Base64.strict_encode64(scanned_document.enhanced_image.download)
      "data:#{content_type};base64,#{encoded}"
    end

    private

    attr_reader :scanned_document
  end
end
