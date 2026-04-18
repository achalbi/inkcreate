require "test_helper"

class ScannedDocuments::ApplyOcrResultTest < ActiveSupport::TestCase
  test "estimates confidence when OCR providers do not return one" do
    user = User.create!(
      email: "apply-ocr-result-confidence@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )

    doc = ScannedDocument.create!(
      user: user,
      title: "Dinner menu",
      enhanced_image: ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("image"),
        filename: "menu.jpg",
        content_type: "image/jpeg"
      ),
      document_pdf: ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("%PDF-1.4 menu"),
        filename: "menu.pdf",
        content_type: "application/pdf"
      )
    )

    ScannedDocuments::ApplyOcrResult.new(
      scanned_document: doc,
      text: <<~TEXT,
        VEG STARTER
        MASALA VADA
        CHILLY BAJJI
        ONION PAKODA
        PANEER CHILLY
      TEXT
      engine: "google-ml",
      language: "eng",
      confidence: nil
    ).call

    doc.reload

    assert doc.ocr_confidence.present?
    assert_operator doc.ocr_confidence, :>=, 80.0
  ensure
    doc&.enhanced_image&.purge
    doc&.document_pdf&.purge
  end
end
