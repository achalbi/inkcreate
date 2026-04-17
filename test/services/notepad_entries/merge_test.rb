require "test_helper"

module NotepadEntries
  class MergeTest < ActiveSupport::TestCase
    test "keeps the primary title and appends the secondary content buckets" do
      user = User.create!(
        email: "merge-service@example.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        time_zone: "UTC",
        locale: "en",
        role: :user
      )

      primary_entry = user.notepad_entries.create!(
        title: "Primary page",
        notes: "<div>Primary note</div>",
        entry_date: Date.new(2026, 4, 16)
      )
      secondary_entry = user.notepad_entries.create!(
        title: "Secondary page",
        notes: "<div>Secondary note</div>",
        entry_date: Date.new(2026, 4, 17)
      )

      primary_entry.photos.attach(
        io: StringIO.new("primary-photo"),
        filename: "primary.jpg",
        content_type: "image/jpeg"
      )
      secondary_entry.photos.attach(
        io: StringIO.new("secondary-photo"),
        filename: "secondary.jpg",
        content_type: "image/jpeg"
      )

      primary_list = primary_entry.create_todo_list!(enabled: true, hide_completed: false)
      primary_list.todo_items.create!(content: "Primary task", position: 1)

      secondary_list = secondary_entry.create_todo_list!(enabled: true, hide_completed: false)
      secondary_list.todo_items.create!(content: "Secondary task", position: 1)

      voice_note = secondary_entry.voice_notes.new(
        duration_seconds: 12,
        recorded_at: Time.zone.parse("2026-04-17 09:00:00"),
        byte_size: 4,
        mime_type: "audio/webm"
      )
      voice_note.audio.attach(
        io: StringIO.new("note"),
        filename: "note.webm",
        content_type: "audio/webm"
      )
      voice_note.save!

      scanned_document = secondary_entry.scanned_documents.new(
        user: user,
        title: "Receipt"
      )
      scanned_document.enhanced_image.attach(
        io: StringIO.new("image"),
        filename: "receipt.jpg",
        content_type: "image/jpeg"
      )
      scanned_document.document_pdf.attach(
        io: StringIO.new("%PDF-1.4\n%%EOF\n".b),
        filename: "receipt.pdf",
        content_type: "application/pdf"
      )
      scanned_document.save!

      NotepadEntries::Merge.new(
        primary_entry: primary_entry,
        secondary_entry: secondary_entry
      ).call

      primary_entry.reload

      assert_equal "Primary page", primary_entry.title
      assert_match "Primary note", primary_entry.plain_notes
      assert_match "Secondary note", primary_entry.plain_notes
      assert_equal 2, primary_entry.photos.count
      assert_equal ["Primary task", "Secondary task"], primary_entry.todo_list.display_todo_items.pluck(:content)
      assert_equal 1, primary_entry.voice_notes.count
      assert_equal 1, primary_entry.scanned_documents.count
      assert_not NotepadEntry.exists?(secondary_entry.id)
    end
  end
end
