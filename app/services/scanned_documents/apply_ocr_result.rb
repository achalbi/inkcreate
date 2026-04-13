module ScannedDocuments
  class ApplyOcrResult
    SUPPORTED_ENGINES = %w[tesseract google-ml cloud-vision].freeze

    def initialize(scanned_document:, text:, engine: nil, language: nil, confidence: nil)
      @scanned_document = scanned_document
      @text = text
      @engine = engine
      @language = language
      @confidence = confidence
    end

    def call
      cleaned_text = normalize_text
      raise ArgumentError, "OCR returned no text." if cleaned_text.blank?

      scanned_document.update!(
        extracted_text: cleaned_text,
        ocr_engine: normalize_engine,
        ocr_language: normalize_language,
        ocr_confidence: normalize_confidence
      )

      scanned_document
    end

    private

    attr_reader :confidence, :engine, :language, :scanned_document, :text

    def normalize_text
      text.to_s
        .gsub(/\r\n?/, "\n")
        .gsub(/[ \t]+/, " ")
        .gsub(/\n{3,}/, "\n\n")
        .strip
    end

    def normalize_engine
      selected = engine.to_s.presence || "google-ml"
      SUPPORTED_ENGINES.include?(selected) ? selected : "google-ml"
    end

    def normalize_language
      language.to_s.presence || ENV.fetch("OCR_LANGUAGE", "eng")
    end

    def normalize_confidence
      return nil if confidence.blank?

      value = confidence.to_f
      value *= 100 if value.positive? && value <= 1
      value.clamp(0.0, 100.0)
    end
  end
end
