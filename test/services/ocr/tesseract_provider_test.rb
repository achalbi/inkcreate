require "test_helper"

class Ocr::TesseractProviderTest < ActiveSupport::TestCase
  test "extracts mean confidence from tesseract tsv output" do
    provider = Ocr::TesseractProvider.new
    tsv = <<~TSV
      level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext
      1\t1\t0\t0\t0\t0\t0\t0\t100\t100\t-1\t
      5\t1\t1\t1\t1\t1\t10\t10\t20\t10\t96.4\tHello
      5\t1\t1\t1\t1\t2\t40\t10\t20\t10\t87.6\tWorld
      5\t1\t1\t1\t1\t3\t70\t10\t20\t10\t-1\t
    TSV

    engine = Struct.new(:tsv_text) do
      def to_s
        "Hello World"
      end

      def to_tsv
        StringIO.new(tsv_text)
      end
    end.new(tsv)

    RTesseract.stub(:new, engine) do
      result = provider.call(image_path: "/tmp/sample.jpg")

      assert_equal "Hello World", result.cleaned_text
      assert_in_delta 92.0, result.mean_confidence, 0.001
      assert_equal "tesseract", result.metadata[:provider]
    end
  end

  test "returns nil confidence when tsv parsing fails" do
    provider = Ocr::TesseractProvider.new

    engine = Struct.new(:tsv_text) do
      def to_s
        "Hello World"
      end

      def to_tsv
        StringIO.new(tsv_text)
      end
    end.new("not-a-valid-tsv")

    RTesseract.stub(:new, engine) do
      result = provider.call(image_path: "/tmp/sample.jpg")

      assert_nil result.mean_confidence
    end
  end
end
