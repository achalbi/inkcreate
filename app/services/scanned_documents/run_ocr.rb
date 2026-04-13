module ScannedDocuments
  class RunOcr
    def initialize(scanned_document:)
      @scanned_document = scanned_document
    end

    def call
      raise ArgumentError, "Scanned document image is missing" unless scanned_document.enhanced_image.attached?

      source_file = download_source_image
      processed_file = Ocr::ImagePreprocessor.new(source_path: source_file.path).call
      provider_result = Ocr::TesseractProvider.new.call(image_path: processed_file.path)

      ApplyOcrResult.new(
        scanned_document:,
        text: provider_result.cleaned_text,
        engine: provider_result.metadata[:provider],
        language: provider_result.language,
        confidence: provider_result.mean_confidence
      ).call

      provider_result
    ensure
      source_file&.close!
      processed_file&.close!
    end

    private

    attr_reader :scanned_document

    def download_source_image
      tempfile = Tempfile.new(["scanned-document-ocr", File.extname(scanned_document.enhanced_image.filename.to_s).presence || ".jpg"])
      tempfile.binmode
      tempfile.write(scanned_document.enhanced_image.download)
      tempfile.rewind
      tempfile
    end
  end
end
