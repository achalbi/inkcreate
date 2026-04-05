module Ocr
  class TesseractProvider
    def call(image_path:)
      raw_text = RTesseract.new(image_path, lang: ENV.fetch("OCR_LANGUAGE", "eng"), psm: 6, oem: 1).to_s
      cleaned_text = raw_text
        .gsub(/[ \t]+/, " ")
        .gsub(/\n{3,}/, "\n\n")
        .strip

      ProviderResult.new(
        raw_text: raw_text,
        cleaned_text: cleaned_text,
        mean_confidence: nil,
        language: ENV.fetch("OCR_LANGUAGE", "eng"),
        metadata: {
          provider: "tesseract",
          engine_mode: 1,
          page_segmentation_mode: 6
        }
      )
    end
  end
end
