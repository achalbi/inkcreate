module ScannedDocuments
  class PdfBuilder
    DEFAULT_WIDTH = 612
    DEFAULT_HEIGHT = 792
    JPEG_START_OF_FRAME_MARKERS = [
      0xC0, 0xC1, 0xC2, 0xC3,
      0xC5, 0xC6, 0xC7,
      0xC9, 0xCA, 0xCB,
      0xCD, 0xCE, 0xCF
    ].freeze

    def initialize(image_binary:)
      @image_binary = image_binary
    end

    def call
      width, height = image_dimensions
      build_pdf(width: width, height: height)
    end

    private

    attr_reader :image_binary

    def image_dimensions
      jpeg_dimensions || png_dimensions || [DEFAULT_WIDTH, DEFAULT_HEIGHT]
    end

    def png_dimensions
      return unless image_binary.start_with?("\x89PNG\r\n\x1A\n".b)
      return unless image_binary.bytesize >= 24

      width = image_binary.byteslice(16, 4)&.unpack1("N")
      height = image_binary.byteslice(20, 4)&.unpack1("N")
      return unless width.to_i.positive? && height.to_i.positive?

      [width, height]
    rescue StandardError
      nil
    end

    def jpeg_dimensions
      bytes = image_binary.b
      return unless bytes.bytesize >= 4
      return unless bytes.getbyte(0) == 0xFF && bytes.getbyte(1) == 0xD8

      offset = 2

      while offset < bytes.bytesize
        offset += 1 while offset < bytes.bytesize && bytes.getbyte(offset) == 0xFF
        break if offset >= bytes.bytesize

        marker = bytes.getbyte(offset)
        offset += 1

        next if marker == 0x01 || (0xD0..0xD9).cover?(marker)
        break if offset + 1 >= bytes.bytesize

        segment_length = bytes.byteslice(offset, 2).unpack1("n")
        break if segment_length.to_i < 2 || offset + segment_length > bytes.bytesize

        if JPEG_START_OF_FRAME_MARKERS.include?(marker)
          height = bytes.byteslice(offset + 3, 2).unpack1("n")
          width = bytes.byteslice(offset + 5, 2).unpack1("n")
          return [width, height] if width.to_i.positive? && height.to_i.positive?
          break
        end

        offset += segment_length
      end

      nil
    rescue StandardError
      nil
    end

    def build_pdf(width:, height:)
      content_stream = +"q\n#{width} 0 0 #{height} 0 0 cm\n/Im0 Do\nQ\n"

      objects = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 #{width} #{height}] /Resources << /XObject << /Im0 5 0 R >> >> /Contents 4 0 R >>",
        "<< /Length #{content_stream.bytesize} >>\nstream\n#{content_stream}endstream",
        "<< /Type /XObject /Subtype /Image /Width #{width} /Height #{height} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length #{image_binary.bytesize} >>\nstream\n#{image_binary}endstream"
      ]

      pdf = String.new(capacity: image_binary.bytesize + 1024, encoding: Encoding::BINARY)
      pdf << "%PDF-1.4\n%\xFF\xFF\xFF\xFF\n".b

      offsets = []
      objects.each_with_index do |object, index|
        offsets << pdf.bytesize
        pdf << "#{index + 1} 0 obj\n".b
        pdf << object.b
        pdf << "\nendobj\n".b
      end

      xref_offset = pdf.bytesize
      pdf << "xref\n0 #{objects.length + 1}\n".b
      pdf << "0000000000 65535 f \n".b
      offsets.each do |offset|
        pdf << format("%010d 00000 n \n", offset).b
      end
      pdf << "trailer\n<< /Size #{objects.length + 1} /Root 1 0 R >>\n".b
      pdf << "startxref\n#{xref_offset}\n%%EOF\n".b
      pdf
    end
  end
end
