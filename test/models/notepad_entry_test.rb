require "test_helper"

class NotepadEntryTest < ActiveSupport::TestCase
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

  test "requires notes, a location, a contact, a photo, a voice note, or a to-do item" do
    user = build_user(email: "notes@example.com")

    entry = user.notepad_entries.new(entry_date: Date.current)

    assert_not entry.valid?
    assert_includes entry.errors.full_messages, "Add notes, a location, a contact, a photo, a scanned document, a voice note, or a to-do item."
  end

  test "generated title alone does not satisfy content validation" do
    user = build_user(email: "dated-title-only@example.com")

    entry = user.notepad_entries.new(
      entry_date: Date.new(2026, 4, 5),
      title: ""
    )

    assert_not entry.valid?
    assert_equal "Sunday, Apr 5 - Page 1", entry.title
    assert_includes entry.errors.full_messages, "Add notes, a location, a contact, a photo, a scanned document, a voice note, or a to-do item."
  end

  test "allows a blank daily page shell when explicitly requested" do
    user = build_user(email: "blank-shell@example.com")

    entry = user.notepad_entries.new(
      entry_date: Date.new(2026, 4, 5),
      title: ""
    )
    entry.allow_blank_content = true

    assert entry.valid?
    assert_equal "Sunday, Apr 5 - Page 1", entry.title
  end

  test "generates a title from notes when blank" do
    user = build_user(email: "generated-title@example.com")

    entry = user.notepad_entries.create!(
      entry_date: Date.new(2026, 4, 5),
      title: "",
      notes: "Discussed rollout sequencing and next actions for the capture experience."
    )

    assert_equal "Discussed rollout sequencing and next actions for the... - Page 1", entry.title
  end

  test "generates a title from location when notes are blank" do
    user = build_user(email: "location-title@example.com")

    entry = user.notepad_entries.create!(
      entry_date: Date.new(2026, 4, 5),
      title: "",
      location_name: "Inkcreate HQ",
      location_address: "Inkcreate HQ, Bengaluru, Karnataka, India"
    )

    assert_equal "Inkcreate HQ - Page 1", entry.title
  end

  test "is valid with only a location check-in" do
    user = build_user(email: "location-checkin@example.com")

    entry = user.notepad_entries.new(
      entry_date: Date.current,
      title: "",
      location_name: "Client office",
      location_address: "Client office, MG Road, Bengaluru",
      location_latitude: 12.9753,
      location_longitude: 77.6050,
      location_source: "current"
    )

    assert entry.valid?
  end

  test "generates a title from contact when notes are blank" do
    user = build_user(email: "contact-title@example.com")

    entry = user.notepad_entries.create!(
      entry_date: Date.new(2026, 4, 5),
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

    assert_equal "Ada Lovelace - Page 1", entry.title
  end

  test "is valid with only contacts" do
    user = build_user(email: "contact-only@example.com")

    entry = user.notepad_entries.new(
      entry_date: Date.current,
      title: "",
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

    assert entry.valid?
  end

  test "stores multiple contacts and normalizes website urls" do
    user = build_user(email: "multi-contact-entry@example.com")

    entry = user.notepad_entries.create!(
      entry_date: Date.new(2026, 4, 5),
      title: "",
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

    assert_equal 2, entry.contact_count
    assert_equal "Ada Lovelace", entry.contact_label
    assert_equal ["Ada Lovelace", "Grace Hopper"], entry.contact_entries.map { |contact| contact[:name] }
    assert_equal "https://example.com", entry.contact_entries.first[:website_url]
  end

  test "stores multiple locations and mirrors the first location onto legacy fields" do
    user = build_user(email: "multi-location-entry@example.com")

    entry = user.notepad_entries.create!(
      entry_date: Date.new(2026, 4, 5),
      title: "",
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

    assert_equal 2, entry.location_count
    assert_equal "Inkcreate HQ", entry.location_name
    assert_equal "search", entry.location_source
    assert_equal ["Inkcreate HQ", "Client office"], entry.location_entries.map { |location| location[:label] }
  end

  test "preserves multiple locations after attaching photos" do
    user = build_user(email: "multi-location-entry-attachments@example.com")

    entry = user.notepad_entries.create!(
      entry_date: Date.new(2026, 4, 5),
      title: "",
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

    entry.photos.attach(
      io: StringIO.new("fake image bytes"),
      filename: "entry.jpg",
      content_type: "image/jpeg"
    )

    entry.reload

    assert_equal 2, entry.location_count
    assert_equal ["Inkcreate HQ", "Client office"], entry.location_entries.map { |location| location[:label] }
  end

  test "is valid with a retained pending photo and no notes" do
    user = build_user(email: "retained-photo@example.com")
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("fake image bytes"),
      filename: "entry.jpg",
      content_type: "image/jpeg"
    )

    entry = user.notepad_entries.new(entry_date: Date.current, title: "")
    entry.retained_photo_signed_ids = [blob.signed_id]

    assert entry.valid?
  ensure
    blob&.purge
  end

  test "is valid with a pending voice note and no notes or photos" do
    user = build_user(email: "retained-voice-note@example.com")

    entry = user.notepad_entries.new(entry_date: Date.current, title: "")
    entry.pending_voice_note_uploads = [Object.new]

    assert entry.valid?
  end

  test "is valid with pending scanned documents and no notes or photos" do
    user = build_user(email: "retained-scan@example.com")

    entry = user.notepad_entries.new(entry_date: Date.current, title: "")
    entry.pending_scanned_document_payloads = [{
      "title" => "Receipt",
      "extracted_text" => "Total: 42.00",
      "image_data" => "data:image/jpeg;base64,#{Base64.strict_encode64('scan-bytes')}"
    }]

    assert entry.valid?
  end

  test "is valid with pending to-do items and no notes, photos, or voice notes" do
    user = build_user(email: "retained-todo-item@example.com")

    entry = user.notepad_entries.new(entry_date: Date.current, title: "")
    entry.pending_todo_list_enabled = true
    entry.pending_todo_item_contents = ["Draft checklist item"]

    assert entry.valid?
  end

  test "uses the running page number in the generated suffix" do
    user = build_user(email: "entry-running-number@example.com")
    user.notepad_entries.create!(
      entry_date: Date.new(2026, 4, 5),
      title: "",
      notes: "First captured entry"
    )

    entry = user.notepad_entries.create!(
      entry_date: Date.new(2026, 4, 5),
      title: "",
      notes: "Second captured entry"
    )

    assert_equal "Second captured entry - Page 2", entry.title
  end
end
