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
    assert_includes page.errors.full_messages, "Add notes, a location, a contact, a photo, a scanned document, a voice note, or a to-do item."
  end

  test "generates a title from location when notes are blank" do
    chapter = build_chapter(email: "page-location-title@example.com")

    page = chapter.pages.create!(
      title: "",
      location_name: "Inkcreate HQ",
      location_address: "Inkcreate HQ, Bengaluru, Karnataka, India"
    )

    assert_equal "Inkcreate HQ - Page 1", page.title
    assert_equal "Inkcreate HQ - Page 1", page.display_title
  end

  test "is valid with only a location check-in" do
    chapter = build_chapter(email: "page-location-checkin@example.com")
    page = chapter.pages.new(
      title: "",
      captured_on: Date.current,
      location_name: "Client office",
      location_address: "Client office, MG Road, Bengaluru",
      location_latitude: 12.9753,
      location_longitude: 77.6050,
      location_source: "current"
    )

    assert page.valid?
  end

  test "generates a title from contact when notes are blank" do
    chapter = build_chapter(email: "page-contact-title@example.com")

    page = chapter.pages.create!(
      title: "",
      contacts_json: [
        {
          name: "Ada Lovelace",
          primary_phone: "+1 555 010 2000",
          email: "ada@example.com",
          website: "example.com"
        }
      ].to_json
    )

    assert_equal "Ada Lovelace - Page 1", page.title
    assert_equal "Ada Lovelace - Page 1", page.display_title
  end

  test "is valid with only contacts" do
    chapter = build_chapter(email: "page-contact-only@example.com")
    page = chapter.pages.new(
      title: "",
      captured_on: Date.current,
      contacts_json: [
        {
          name: "Grace Hopper",
          primary_phone: "+1 555 010 3000",
          secondary_phone: "+1 555 010 4000",
          email: "grace@example.com",
          website: "gracehopper.dev"
        }
      ].to_json
    )

    assert page.valid?
  end

  test "stores multiple contacts and normalizes website urls" do
    chapter = build_chapter(email: "page-multiple-contacts@example.com")

    page = chapter.pages.create!(
      title: "",
      captured_on: Date.new(2026, 4, 5),
      contacts_json: [
        {
          name: "Ada Lovelace",
          primary_phone: "+1 555 010 2000",
          email: "ada@example.com",
          website: "example.com"
        },
        {
          name: "Grace Hopper",
          secondary_phone: "+1 555 010 4000",
          website: "https://gracehopper.dev"
        }
      ].to_json
    )

    assert_equal 2, page.contact_count
    assert_equal "Ada Lovelace", page.contact_label
    assert_equal ["Ada Lovelace", "Grace Hopper"], page.contact_entries.map { |contact| contact[:name] }
    assert_equal "https://example.com", page.contact_entries.first[:website_url]
  end

  test "stores multiple locations and mirrors the first location onto legacy fields" do
    chapter = build_chapter(email: "page-multiple-locations@example.com")

    page = chapter.pages.create!(
      title: "",
      captured_on: Date.new(2026, 4, 5),
      locations_json: [
        {
          name: "Inkcreate HQ",
          address: "Inkcreate HQ, MG Road, Bengaluru, Karnataka, India",
          latitude: "12.975300",
          longitude: "77.605000",
          source: "search"
        },
        {
          name: "Client office",
          address: "Client office, 12 Main St, Austin, TX",
          latitude: "30.267200",
          longitude: "-97.743100",
          source: "manual"
        }
      ].to_json
    )

    assert_equal 2, page.location_count
    assert_equal "Inkcreate HQ", page.location_name
    assert_equal "search", page.location_source
    assert_equal ["Inkcreate HQ", "Client office"], page.location_entries.map { |location| location[:label] }
  end

  test "preserves multiple locations after attaching photos" do
    chapter = build_chapter(email: "page-multi-location-attachments@example.com")

    page = chapter.pages.create!(
      title: "",
      captured_on: Date.new(2026, 4, 5),
      locations_json: [
        {
          name: "Inkcreate HQ",
          address: "Inkcreate HQ, MG Road, Bengaluru, Karnataka, India",
          latitude: "12.975300",
          longitude: "77.605000",
          source: "search"
        },
        {
          name: "Client office",
          address: "Client office, 12 Main St, Austin, TX",
          latitude: "30.267200",
          longitude: "-97.743100",
          source: "manual"
        }
      ].to_json
    )

    page.photos.attach(
      io: StringIO.new("fake image bytes"),
      filename: "page.jpg",
      content_type: "image/jpeg"
    )

    page.reload

    assert_equal 2, page.location_count
    assert_equal ["Inkcreate HQ", "Client office"], page.location_entries.map { |location| location[:label] }
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
