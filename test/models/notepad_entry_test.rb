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

  test "requires notes, a photo, a voice note, or a to-do item" do
    user = build_user(email: "notes@example.com")

    entry = user.notepad_entries.new(entry_date: Date.current)

    assert_not entry.valid?
    assert_includes entry.errors.full_messages, "Add notes, a photo, a scanned document, a voice note, or a to-do item."
  end

  test "generated title alone does not satisfy content validation" do
    user = build_user(email: "dated-title-only@example.com")

    entry = user.notepad_entries.new(
      entry_date: Date.new(2026, 4, 5),
      title: ""
    )

    assert_not entry.valid?
    assert_equal "Sunday, Apr 5 - Page 1", entry.title
    assert_includes entry.errors.full_messages, "Add notes, a photo, a scanned document, a voice note, or a to-do item."
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
