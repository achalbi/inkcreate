require "test_helper"

class PageTest < ActiveSupport::TestCase
  def build_chapter(email:)
    user = User.create!(
      email: email,
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )

    notebook = user.notebooks.create!(
      title: "Research notebook",
      description: "Discovery notes",
      status: :active
    )

    notebook.chapters.create!(
      title: "Interviews"
    )
  end

  test "generates a title from notes when blank" do
    chapter = build_chapter(email: "page-generated-title@example.com")

    page = chapter.pages.create!(
      title: "",
      notes: "Captured follow-up questions and quotes from the stakeholder conversation."
    )

    assert_equal "Captured follow-up questions and quotes from the... - Page 1", page.title
    assert_equal "Captured follow-up questions and quotes from the... - Page 1", page.display_title
  end

  test "requires some form of content" do
    chapter = build_chapter(email: "page-empty-content@example.com")

    page = chapter.pages.new(
      title: "",
      captured_on: Date.new(2026, 4, 5)
    )

    assert_not page.valid?
    assert_equal "Apr 5, 2026 - Page 1", page.title
    assert_equal "Apr 5, 2026 - Page 1", page.display_title
    assert_includes page.errors.full_messages, "Add notes, a photo, a scanned document, a voice note, or a to-do item."
  end

  test "generates a title from captured date when notes are blank" do
    chapter = build_chapter(email: "page-date-title@example.com")
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("fake image bytes"),
      filename: "page.jpg",
      content_type: "image/jpeg"
    )

    page = chapter.pages.new(title: "", captured_on: Date.new(2026, 4, 5))
    page.retained_photo_signed_ids = [blob.signed_id]
    page.save!

    assert_equal "Apr 5, 2026 - Page 1", page.title
    assert_equal "Apr 5, 2026 - Page 1", page.display_title
  ensure
    blob&.purge
  end

  test "uses the running page number in the generated suffix" do
    chapter = build_chapter(email: "page-running-number@example.com")
    chapter.pages.create!(title: "Existing page", notes: "Original page content")

    page = chapter.pages.create!(
      title: "",
      notes: "Second generated page title"
    )

    assert_equal "Second generated page title - Page 2", page.title
    assert_equal "Second generated page title - Page 2", page.display_title
  end

  test "is valid with a retained pending photo and no notes" do
    chapter = build_chapter(email: "page-retained-photo@example.com")
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("fake image bytes"),
      filename: "page.jpg",
      content_type: "image/jpeg"
    )

    page = chapter.pages.new(title: "", captured_on: Date.current)
    page.retained_photo_signed_ids = [blob.signed_id]

    assert page.valid?
  ensure
    blob&.purge
  end

  test "is valid with a pending voice note upload and no notes or photos" do
    chapter = build_chapter(email: "page-pending-voice-note@example.com")
    page = chapter.pages.new(title: "", captured_on: Date.current)
    page.pending_voice_note_uploads = [Object.new]

    assert page.valid?
  end

  test "is valid with pending scanned documents and no notes or photos" do
    chapter = build_chapter(email: "page-pending-scan@example.com")
    page = chapter.pages.new(title: "", captured_on: Date.current)
    page.pending_scanned_document_payloads = [{
      "title" => "Receipt",
      "extracted_text" => "Total: 42.00",
      "image_data" => "data:image/jpeg;base64,#{Base64.strict_encode64('scan-bytes')}"
    }]

    assert page.valid?
  end

  test "is valid with pending to-do items and no notes or media" do
    chapter = build_chapter(email: "page-pending-todo@example.com")
    page = chapter.pages.new(title: "", captured_on: Date.current)
    page.pending_todo_list_enabled = true
    page.pending_todo_item_contents = ["Draft reminder item"]

    assert page.valid?
  end

  test "allows a blank page shell when explicitly requested" do
    chapter = build_chapter(email: "page-blank-shell@example.com")
    page = chapter.pages.new(title: "", captured_on: Date.new(2026, 4, 5))
    page.allow_blank_content = true

    assert page.valid?
    assert_equal "Apr 5, 2026 - Page 1", page.display_title
  end

  test "adds the current suffix to a manually entered title" do
    chapter = build_chapter(email: "page-manual-title@example.com")

    page = chapter.pages.create!(
      title: "Meeting notes",
      notes: "Reviewed launch checklist."
    )

    assert_equal "Meeting notes - Page 1", page.title
    assert_equal "Meeting notes - Page 1", page.display_title
  end
end
