module Ocr
  class ProviderFactory
    def self.build(provider_name)
      case provider_name
      when "tesseract"
        TesseractProvider.new
      when "google_vision"
        raise NotImplementedError, "Google Vision provider not implemented yet"
      else
        raise ArgumentError, "Unsupported OCR provider: #{provider_name}"
      end
    end
  end
end
