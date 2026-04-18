module Ocr
  class TesseractProvider
    def call(image_path:)
      engine = RTesseract.new(image_path, lang: ENV.fetch("OCR_LANGUAGE", "eng"), psm: 6, oem: 1)
      raw_text = engine.to_s
      cleaned_text = raw_text
        .gsub(/[ \t]+/, " ")
        .gsub(/\n{3,}/, "\n\n")
        .strip

      ProviderResult.new(
        raw_text: raw_text,
        cleaned_text: cleaned_text,
        mean_confidence: extract_mean_confidence(engine),
        language: ENV.fetch("OCR_LANGUAGE", "eng"),
        metadata: {
          provider: "tesseract",
          engine_mode: 1,
          page_segmentation_mode: 6
        }
      )
    end

    private

    def extract_mean_confidence(engine)
      tsv_io = engine.to_tsv
      tsv_data = tsv_io.read
      tsv_io.close if tsv_io.respond_to?(:close)

      rows = parse_tsv_rows(tsv_data)
      confidences = rows.filter_map do |row|
        next unless word_confidence_row?(row["level"], row["text"])

        value = row["conf"].to_f
        next unless value.finite? && value >= 0

        value
      end

      return nil if confidences.empty?

      (confidences.sum / confidences.length).round(1)
    rescue StandardError
      nil
    end

    def parse_tsv_rows(tsv_data)
      lines = tsv_data.to_s.lines.map(&:chomp)
      return [] if lines.size < 2

      headers = lines.shift.split("\t")
      lines.map do |line|
        values = line.split("\t", headers.length)
        headers.zip(values).to_h
      end
    end

    def word_confidence_row?(level, text)
      return false if text.blank?

      level.to_i == 5
    end
  end
end
