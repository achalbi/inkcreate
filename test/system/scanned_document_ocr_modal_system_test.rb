require "application_system_test_case"

class ScannedDocumentOcrModalSystemTest < ApplicationSystemTestCase
  test "page OCR actions open in a modal, save edits, and confirm delete" do
    user = build_user(email: "page-ocr-modal@example.com")
    notebook = user.notebooks.create!(title: "Paper trail", status: :active)
    chapter = notebook.chapters.create!(title: "Receipts", description: "Captured scans")
    page_record = chapter.pages.create!(title: "Expense scans", notes: "April receipts", captured_on: Date.current)
    scanned_document = page_record.scanned_documents.new(
      user: user,
      title: "Receipt",
      extracted_text: "Vendor: Inkcreate Supplies\nTotal: 42.00",
      ocr_engine: "tesseract",
      ocr_language: "eng",
      ocr_confidence: 88
    )
    scanned_document.enhanced_image.attach(
      io: StringIO.new("image"),
      filename: "receipt.jpg",
      content_type: "image/jpeg"
    )
    scanned_document.document_pdf.attach(
      io: StringIO.new("%PDF-1.4 receipt"),
      filename: "receipt.pdf",
      content_type: "application/pdf"
    )
    scanned_document.save!

    sign_in_as(user)
    visit notebook_chapter_page_path(notebook, chapter, page_record)

    click_link "View OCR"

    within ".sdoc-ocr-modal.show" do
      assert_text "View OCR text", wait: 10
      assert_text "Vendor: Inkcreate Supplies"
      click_link "Edit OCR"
    end

    within ".sdoc-ocr-modal.show" do
      assert_text "Edit OCR text", wait: 10
      find("textarea.sdoc-text-area").set("Updated OCR text")
      click_button "Save changes"
    end

    within ".sdoc-ocr-modal.show" do
      assert_text "OCR text saved.", wait: 10
      assert_text "Updated OCR text"
      click_link "Delete OCR"
    end

    within ".sdoc-ocr-modal.show" do
      assert_text "Delete OCR text?", wait: 10
      click_button "Delete OCR"
    end

    assert_current_path notebook_chapter_page_path(notebook, chapter, page_record), wait: 10
    assert_nil scanned_document.reload.extracted_text

    within "##{ActionView::RecordIdentifier.dom_id(scanned_document)}" do
      assert_no_text "View OCR"
      assert_no_text "Edit OCR"
      assert_no_text "Delete OCR"
      assert_text "Run OCR"
    end
  end

  private

  def build_user(email:)
    User.create!(
      email: email,
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )
  end
end
