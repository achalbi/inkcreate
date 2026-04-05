module Ocr
  class ImagePreprocessor
    def initialize(source_path:)
      @source_path = source_path
    end

    def call
      processed = Tempfile.new(["ocr-preprocessed", ".png"])
      image = MiniMagick::Image.open(source_path)
      image.auto_orient
      image.strip
      image.colorspace("Gray")
      image.density(300)
      image.contrast
      image.write(processed.path)
      processed
    end

    private

    attr_reader :source_path
  end
end
