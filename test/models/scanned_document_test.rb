require "test_helper"

class ScannedDocumentTest < ActiveSupport::TestCase
  test "estimates confidence from extracted text when persisted confidence is blank" do
    doc = ScannedDocument.new(
      extracted_text: <<~TEXT
        VEG STARTER
        MASALA VADA
        CHILLY BAJJI
        ONION PAKODA
        PANEER CHILLY
      TEXT
    )

    assert_equal "high", doc.confidence_class
    assert_match(/\A\d+%\z/, doc.confidence_label)
    refute_equal "—", doc.confidence_label
  end

  test "uses persisted confidence for label and class when available" do
    doc = ScannedDocument.new(
      extracted_text: "Short OCR text",
      ocr_confidence: 42.4
    )

    assert_equal "42%", doc.confidence_label
    assert_equal "low", doc.confidence_class
  end
end
