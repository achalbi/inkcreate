require "application_system_test_case"

class VoiceNotesSystemTest < ApplicationSystemTestCase
  test "user can record a voice note before the first page save and play it back later" do
    user = build_user(email: "voice-system@example.com")
    notebook = user.notebooks.create!(title: "Discovery", status: :active)
    chapter = notebook.chapters.create!(title: "Interviews", description: "Audio capture")

    sign_in_as(user)
    visit new_notebook_chapter_page_path(notebook, chapter)

    click_button "Record"
    click_button "Stop"

    assert_text "Review the recording and save it when ready."

    click_button "Save voice note"

    assert_text "Voice note added to this form."
    assert_selector ".voice-note-recorder__pending-item", count: 1

    assert_difference -> { chapter.pages.count }, 1 do
      find(".workspace-form-actions input[type='submit'][value='Save']").click
      assert_text "Page created.", wait: 10
    end

    entry_page = chapter.pages.order(:created_at).last

    assert_current_path notebook_chapter_page_path(notebook, chapter, entry_page)
    assert_text "Voice notes"
    assert_selector ".voice-note-player", minimum: 1

    assert_equal 1, entry_page.reload.voice_notes.count
    assert entry_page.voice_notes.first.audio.attached?
  end

  test "user can record a voice note from quick capture and open the created daily page in edit mode" do
    user = build_user(email: "quick-capture-voice@example.com")

    sign_in_as(user)
    visit capture_studio_path

    click_button "Record voice note"
    click_button "Stop"

    assert_text "Review the recording and save it when ready."

    click_button "Save voice note"

    assert_text "Daily page created.", wait: 10
    assert_current_path %r{/notepad/[^/]+/edit}, wait: 10

    entry = user.notepad_entries.order(:created_at).last

    assert_not_nil entry
    assert_current_path edit_notepad_entry_path(entry)
    assert_text "Voice notes"
    assert_selector ".voice-note-player", minimum: 1

    assert_equal 1, entry.reload.voice_notes.count
    assert entry.voice_notes.first.audio.attached?
  end

  test "user can save a voice note directly from an existing daily page edit screen" do
    user = build_user(email: "existing-entry-voice@example.com")
    entry = user.notepad_entries.create!(
      title: "Existing daily page",
      notes: "Already saved.",
      entry_date: Date.current
    )

    sign_in_as(user)
    visit edit_notepad_entry_path(entry)

    click_button "Record"
    click_button "Stop"

    assert_text "Review the recording and save it when ready."

    click_button "Save voice note"

    assert_current_path edit_notepad_entry_path(entry), wait: 10
    assert_selector ".voice-note-player", minimum: 1
    assert_no_text "Voice note added to this form."

    assert_equal 1, entry.reload.voice_notes.count
    assert entry.voice_notes.first.audio.attached?
  end

  test "user confirms voice note deletion from a modal" do
    user = build_user(email: "voice-delete@example.com")
    entry = user.notepad_entries.create!(
      title: "Voice note entry",
      notes: "Has an audio note.",
      entry_date: Date.current
    )
    voice_note = entry.voice_notes.new(
      duration_seconds: 18,
      recorded_at: Time.current.change(sec: 0),
      byte_size: 128,
      mime_type: "audio/webm"
    )
    voice_note.audio.attach(
      io: StringIO.new("voice"),
      filename: "note.webm",
      content_type: "audio/webm"
    )
    voice_note.save!
    sign_in_as(user)
    visit edit_notepad_entry_path(entry)

    assert_selector ".voice-note-player", count: 1

    find(".voice-note-player__action--delete").click

    within ".voice-note-delete-confirm-modal.show" do
      assert_text "Delete voice note?"
      click_button "Cancel"
    end

    assert_no_selector ".voice-note-delete-confirm-modal.show", wait: 10
    assert_selector ".voice-note-player", count: 1

    find(".voice-note-player__action--delete").click

    within ".voice-note-delete-confirm-modal.show" do
      click_button "Delete voice note"
    end

    assert_current_path edit_notepad_entry_path(entry), wait: 10
    assert_text "Voice note deleted."
    assert_no_selector ".voice-note-player", wait: 10
    assert_equal 0, entry.reload.voice_notes.count
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
