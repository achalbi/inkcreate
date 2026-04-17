require "test_helper"
require "tempfile"

class NotebookNotepadFlowTest < ActionDispatch::IntegrationTest
  test "user can create notebook chapter page and notepad entry" do
    user = User.create!(
      email: "builder@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )

    sign_in_browser_user(user)
    assert_redirected_to dashboard_path

    get new_notebook_path
    post notebooks_path, params: {
      authenticity_token: authenticity_token_for(notebooks_path),
      notebook: {
        title: "Research notebook",
        description: "User interview synthesis",
        status: "active"
      }
    }

    notebook = user.notebooks.find_by!(title: "Research notebook")
    assert_redirected_to notebook_path(notebook)

    get new_notebook_chapter_path(notebook)
    post notebook_chapters_path(notebook), params: {
      authenticity_token: authenticity_token_for(notebook_chapters_path(notebook)),
      chapter: {
        title: "Insights",
        description: "Top findings"
      }
    }

    chapter = notebook.chapters.find_by!(title: "Insights")
    assert_redirected_to notebook_path(notebook)

    get new_notebook_chapter_page_path(notebook, chapter)
    post notebook_chapter_pages_path(notebook, chapter), params: {
      authenticity_token: authenticity_token_for(notebook_chapter_pages_path(notebook, chapter)),
      page: {
        title: "Interview batch 1",
        notes: "Patterns across first six calls.",
        captured_on: Date.current
      }
    }

    page = chapter.pages.find_by!(title: "Interview batch 1 - Page 1")
    assert_redirected_to notebook_chapter_page_path(notebook, chapter, page)

    get new_notepad_entry_path
    post notepad_entries_path, params: {
      authenticity_token: authenticity_token_for(notepad_entries_path),
      notepad_entry: {
        title: "Daily wrap-up",
        notes: "Three follow-ups for tomorrow.",
        entry_date: Date.current
      }
    }

    entry = user.notepad_entries.find_by!(title: "Daily wrap-up")
    assert_redirected_to notepad_entry_path(entry)
  end

  test "user can create a notepad entry with only a voice note upload" do
    user = User.create!(
      email: "notepad-voice@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )

    sign_in_browser_user(user)

    get capture_studio_path

    upload = audio_upload(filename: "quick-capture-note.webm", content_type: "audio/webm", contents: "voice-note-bytes")

    assert_difference -> { user.notepad_entries.count }, +1 do
      post notepad_entries_path, params: {
        authenticity_token: authenticity_token_for(notepad_entries_path),
        after_create: "edit",
        notepad_entry: {
          title: "",
          notes: "",
          entry_date: Date.current,
          voice_note_uploads: [upload],
          voice_note_duration_seconds: ["42"],
          voice_note_recorded_ats: [Time.current.iso8601]
        }
      }
    end

    entry = user.notepad_entries.order(:created_at).last

    assert_redirected_to edit_notepad_entry_path(entry)
    assert_equal 1, entry.voice_notes.count
    assert entry.voice_notes.first.audio.attached?
    assert_equal 42, entry.voice_notes.first.duration_seconds
  ensure
    upload&.tempfile&.close!
  end

  test "saving the same notepad voice note twice only creates one record" do
    user = User.create!(
      email: "notepad-voice-dedupe@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )
    entry = user.notepad_entries.create!(
      title: "Voice capture",
      notes: "Testing duplicate uploads.",
      entry_date: Date.current
    )

    sign_in_browser_user(user)

    recorded_at = Time.zone.parse("2026-04-15T09:30:00Z").iso8601
    first_upload = audio_upload(filename: "duplicate-note.webm", content_type: "audio/webm", contents: "voice-note-bytes")
    second_upload = audio_upload(filename: "duplicate-note.webm", content_type: "audio/webm", contents: "voice-note-bytes")

    assert_difference -> { entry.voice_notes.count }, +1 do
      post notepad_entry_voice_notes_path(entry), params: {
        authenticity_token: authenticity_token_for(notepad_entry_voice_notes_path(entry)),
        voice_note: {
          audio: first_upload,
          duration_seconds: "14",
          recorded_at: recorded_at
        }
      }
    end

    assert_redirected_to notepad_entry_path(entry)

    assert_no_difference -> { entry.reload.voice_notes.count } do
      post notepad_entry_voice_notes_path(entry), params: {
        authenticity_token: authenticity_token_for(notepad_entry_voice_notes_path(entry)),
        voice_note: {
          audio: second_upload,
          duration_seconds: "14",
          recorded_at: recorded_at
        }
      }
    end

    assert_redirected_to notepad_entry_path(entry)
    assert_equal 1, entry.reload.voice_notes.count
    assert entry.voice_notes.first.audio.attached?
  ensure
    first_upload&.tempfile&.close!
    second_upload&.tempfile&.close!
  end

  test "notepad quick create from index creates the daily page before edit loads" do
    user = User.create!(
      email: "notepad-quick-create@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )

    sign_in_browser_user(user)

    get notepad_entries_path(date: "2026-04-10")

    assert_response :success
    assert_select "form.button_to[action='#{quick_create_notepad_entries_path(date: "2026-04-10")}'] button.workspace-fab", count: 1

    assert_difference -> { user.notepad_entries.count }, +1 do
      post quick_create_notepad_entries_path(date: "2026-04-10"), params: {
        authenticity_token: authenticity_token_for(quick_create_notepad_entries_path(date: "2026-04-10"))
      }
    end

    entry = user.notepad_entries.order(:created_at).last

    assert_redirected_to edit_notepad_entry_path(entry)
    assert_equal Date.new(2026, 4, 10), entry.entry_date
    assert_equal "Friday, Apr 10 - Page 1", entry.title
    assert_equal "", entry.notes.to_s
    follow_redirect!
    assert_response :success

    patch notepad_entry_path(entry), params: {
      authenticity_token: authenticity_token_for(notepad_entry_path(entry)),
      notepad_entry: {
        title: entry.title,
        notes: "",
        entry_date: "2026-04-10"
      }
    }

    assert_redirected_to notepad_entry_path(entry)
  end

  test "user can merge notepad pages and keep the selected page as primary" do
    user = build_user(email: "notepad-merge@example.com")
    current_entry = user.notepad_entries.create!(
      title: "Morning notes",
      notes: "<div>Agenda review</div>",
      entry_date: Date.new(2026, 4, 16)
    )
    selected_entry = user.notepad_entries.create!(
      title: "Afternoon notes",
      notes: "<div>Follow-up tasks</div>",
      entry_date: Date.new(2026, 4, 17)
    )

    sign_in_browser_user(user)

    get notepad_entry_path(current_entry)

    assert_difference -> { user.notepad_entries.count }, -1 do
      post merge_notepad_entry_path(current_entry), params: {
        authenticity_token: authenticity_token_for(merge_notepad_entry_path(current_entry)),
        merge_notepad_entry_id: selected_entry.id,
        merge_primary: "selected"
      }
    end

    assert_redirected_to notepad_entry_path(selected_entry)
    assert_nil user.notepad_entries.find_by(id: current_entry.id)

    selected_entry.reload
    assert_equal "Afternoon notes", selected_entry.title
    assert_match "Follow-up tasks", selected_entry.plain_notes
    assert_match "Agenda review", selected_entry.plain_notes
  end

  test "notebook page quick create from chapter creates the page before edit loads" do
    user = User.create!(
      email: "notebook-page-quick-create@example.com",
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
    chapter = notebook.chapters.create!(title: "Interviews")

    sign_in_browser_user(user)

    get notebook_chapter_path(notebook, chapter)

    assert_response :success
    assert_select "form.button_to[action='#{quick_create_notebook_chapter_pages_path(notebook, chapter)}'] button.workspace-fab", count: 1

    assert_difference -> { chapter.pages.count }, +1 do
      post quick_create_notebook_chapter_pages_path(notebook, chapter), params: {
        authenticity_token: authenticity_token_for(quick_create_notebook_chapter_pages_path(notebook, chapter))
      }
    end

    page = chapter.pages.order(:created_at).last

    assert_redirected_to edit_notebook_chapter_page_path(notebook, chapter, page)
    assert_equal Date.current, page.captured_on
    assert_equal "#{Date.current.strftime("%b %-d, %Y")} - Page 1", page.title
    assert_equal "", page.notes.to_s
    follow_redirect!
    assert_response :success

    patch notebook_chapter_page_path(notebook, chapter, page), params: {
      authenticity_token: authenticity_token_for(notebook_chapter_page_path(notebook, chapter, page)),
      page: {
        title: page.title,
        notes: "",
        captured_on: Date.current
      }
    }

    assert_redirected_to notebook_chapter_page_path(notebook, chapter, page)
  end

  test "user can create a notepad entry with only a to-do list item" do
    user = User.create!(
      email: "notepad-todo@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )

    sign_in_browser_user(user)
    get new_notepad_entry_path

    assert_difference -> { user.notepad_entries.count }, +1 do
      post notepad_entries_path, params: {
        authenticity_token: authenticity_token_for(notepad_entries_path),
        notepad_entry: {
          title: "",
          notes: "",
          entry_date: Date.current,
          todo_list_enabled: "true",
          todo_item_contents: ["Draft checklist item"]
        }
      }
    end

    entry = user.notepad_entries.order(:created_at).last

    assert_redirected_to notepad_entry_path(entry)
    assert entry.todo_list.enabled?
    assert_equal ["Draft checklist item"], entry.todo_list.todo_items.ordered.pluck(:content)
  end

  test "user can create a notepad entry with only scanned documents" do
    user = User.create!(
      email: "notepad-new-scan@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )

    sign_in_browser_user(user)
    get new_notepad_entry_path

    assert_response :success
    assert_select ".notepad-doc__block-label", text: /Scanned documents/
    assert_no_match "Web scan mode", response.body
    assert_no_match "Saved with this form", response.body

    assert_difference -> { user.notepad_entries.count }, +1 do
      post notepad_entries_path, params: {
        authenticity_token: authenticity_token_for(notepad_entries_path),
        notepad_entry: {
          title: "",
          notes: "",
          entry_date: Date.current,
          pending_scanned_documents_json: [scanned_document_payload(title: "Receipt", text: "Total: 42.00")].to_json
        }
      }
    end

    entry = user.notepad_entries.order(:created_at).last

    assert_redirected_to notepad_entry_path(entry)
    assert_equal 1, entry.scanned_documents.count
    assert entry.scanned_documents.first.enhanced_image.attached?
    assert entry.scanned_documents.first.document_pdf.attached?
    assert_equal tiny_pdf_binary, entry.scanned_documents.first.document_pdf.download
    assert_nil entry.scanned_documents.first.extracted_text
  end

  test "user can manage scanned documents on a notepad entry" do
    user = User.create!(
      email: "notepad-scan@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )
    entry = user.notepad_entries.create!(
      title: "Inbox scans",
      notes: "Collect scans here.",
      entry_date: Date.current
    )

    sign_in_browser_user(user)

    get notepad_entry_path(entry)

    assert_response :success
    assert_select ".notepad-doc__block-label", text: /Scanned documents/
    assert_no_match "Web scan mode", response.body
    assert_select "form.button_to[action='#{notepad_entry_scanned_document_path(entry, 'missing')}']", count: 0

    assert_difference -> { entry.scanned_documents.count }, +1 do
      post notepad_entry_scanned_documents_path(entry), params: {
        authenticity_token: authenticity_token_for(notepad_entry_scanned_documents_path(entry)),
        scanned_document: {
          title: "Receipt",
          enhancement_filter: "auto",
          tags: ["receipt", "expense"].to_json,
          image_data: tiny_jpeg_data_url,
          pdf_data: tiny_pdf_data_url
        }
      }
    end

    scanned_document = entry.scanned_documents.order(:created_at).last

    assert_redirected_to notepad_entry_path(entry)
    assert scanned_document.document_pdf.attached?
    assert_equal tiny_pdf_binary, scanned_document.document_pdf.download
    follow_redirect!

    ScannedDocuments::RunOcr.stub :new, ->(scanned_document:) {
      runner = Object.new
      runner.define_singleton_method(:call) do
        scanned_document.update!(
          extracted_text: "Total: 42.00",
          ocr_engine: "tesseract",
          ocr_language: "eng",
          ocr_confidence: 88
        )
      end
      runner
    } do
      post extract_text_notepad_entry_scanned_document_path(entry, scanned_document), params: {
        authenticity_token: authenticity_token_for(extract_text_notepad_entry_scanned_document_path(entry, scanned_document))
      }
    end

    assert_redirected_to notepad_entry_path(entry)
    scanned_document.reload
    assert_equal "Total: 42.00", scanned_document.extracted_text
    assert_equal "tesseract", scanned_document.ocr_engine
    assert_equal "eng", scanned_document.ocr_language
    assert_in_delta 88.0, scanned_document.ocr_confidence, 0.001

    follow_redirect!

    assert_response :success
    assert_select ".sdoc-title", text: "Receipt"
    assert_select ".sdoc-excerpt", count: 0

    assert_difference -> { entry.scanned_documents.count }, -1 do
      delete notepad_entry_scanned_document_path(entry, scanned_document), params: {
        authenticity_token: authenticity_token_for(notepad_entry_scanned_document_path(entry, scanned_document))
      }
    end

    assert_redirected_to notepad_entry_path(entry)
  end

  test "notepad scanned documents auto-title duplicates gain a numeric suffix" do
    user = User.create!(
      email: "notepad-scan-title-suffix@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )
    entry = user.notepad_entries.create!(
      title: "Inbox scans",
      notes: "Collect scans here.",
      entry_date: Date.current
    )
    auto_title = "Scan — Apr 14, 2026 10:15:30"

    sign_in_browser_user(user)
    get notepad_entry_path(entry)
    assert_response :success
    scanned_document_token = authenticity_token_for(notepad_entry_scanned_documents_path(entry))

    post notepad_entry_scanned_documents_path(entry), params: {
      authenticity_token: scanned_document_token,
      scanned_document: {
        title: auto_title,
        enhancement_filter: "auto",
        tags: ["receipt"].to_json,
        image_data: tiny_jpeg_data_url,
        pdf_data: tiny_pdf_data_url
      }
    }

    post notepad_entry_scanned_documents_path(entry), params: {
      authenticity_token: scanned_document_token,
      scanned_document: {
        title: auto_title,
        enhancement_filter: "auto",
        tags: ["receipt"].to_json,
        image_data: tiny_jpeg_data_url,
        pdf_data: tiny_pdf_data_url
      }
    }

    assert_equal [auto_title, "#{auto_title} #2"], entry.scanned_documents.order(:created_at).pluck(:title)
  end

  test "user can store a native OCR result on a notepad scan" do
    user = User.create!(
      email: "notepad-native-ocr@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )
    entry = user.notepad_entries.create!(
      title: "Inbox scans",
      notes: "Collect scans here.",
      entry_date: Date.current
    )

    sign_in_browser_user(user)
    get notepad_entry_path(entry)

    assert_difference -> { entry.scanned_documents.count }, +1 do
      post notepad_entry_scanned_documents_path(entry), params: {
        authenticity_token: authenticity_token_for(notepad_entry_scanned_documents_path(entry)),
        scanned_document: {
          title: "Invoice",
          enhancement_filter: "auto",
          tags: ["invoice"].to_json,
          image_data: tiny_jpeg_data_url,
          pdf_data: tiny_pdf_data_url
        }
      }
    end

    scanned_document = entry.scanned_documents.order(:created_at).last
    follow_redirect!

    post submit_ocr_result_notepad_entry_scanned_document_path(entry, scanned_document), params: {
      authenticity_token: authenticity_token_for(notepad_entry_path(entry)),
      ocr_result: {
        text: "Invoice Total 84.00",
        confidence: 87,
        language: "eng",
        engine: "google-ml"
      }
    }

    assert_redirected_to notepad_entry_path(entry)

    scanned_document.reload
    assert_equal "Invoice Total 84.00", scanned_document.extracted_text
    assert_equal "google-ml", scanned_document.ocr_engine
    assert_equal "eng", scanned_document.ocr_language
    assert_in_delta 87.0, scanned_document.ocr_confidence, 0.001
  end

  test "voice note transcript can be submitted for a notepad entry" do
    user = build_user(email: "notepad-voice-transcript@example.com")
    entry = user.notepad_entries.create!(
      title: "Call recap",
      notes: "Transcript pending",
      entry_date: Date.current
    )
    voice_note = entry.voice_notes.new(
      duration_seconds: 45,
      recorded_at: Time.current.change(sec: 0),
      byte_size: 512,
      mime_type: "audio/webm"
    )
    voice_note.audio.attach(
      io: StringIO.new("voice"),
      filename: "entry-note.webm",
      content_type: "audio/webm"
    )
    voice_note.save!

    sign_in_browser_user(user)
    get notepad_entry_path(entry)

    post submit_transcript_notepad_entry_voice_note_path(entry, voice_note), params: {
      authenticity_token: authenticity_token_for(notepad_entry_path(entry)),
      transcript_result: {
        text: "Discussed blockers, timeline, and rollout owners."
      }
    }

    assert_redirected_to notepad_entry_path(entry)
    assert_equal "Discussed blockers, timeline, and rollout owners.", voice_note.reload.transcript
  end

  test "user cannot access another users notebook" do
    owner = User.create!(
      email: "owner@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )
    intruder = User.create!(
      email: "intruder@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )

    notebook = owner.notebooks.create!(title: "Private notebook")

    sign_in_browser_user(intruder)
    get notebook_path(notebook)

    assert_response :not_found
  end

  test "user can move a notepad entry into a notebook chapter from edit mode" do
    user = User.create!(
      email: "mover@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )

    notebook = user.notebooks.create!(
      title: "Research notebook",
      description: "Project notes",
      status: :active
    )
    chapter = notebook.chapters.create!(title: "Interviews", description: "Conversation logs")

    entry = user.notepad_entries.create!(
      title: "Daily wrap-up",
      notes: "Move this into the project notebook.",
      entry_date: Date.new(2026, 4, 10)
    )
    entry.photos.attach(
      io: StringIO.new("fake image bytes"),
      filename: "entry.jpg",
      content_type: "image/jpeg"
    )

    sign_in_browser_user(user)

    get edit_notepad_entry_path(entry)

    assert_response :success
    assert_select "input[type='hidden'][name='move_to_chapter_id']"
    assert_select "button.notepad-entry-move-picker-button", text: /Choose a notebook and chapter/
    assert_select "[data-move-destination-target='notebookMenu'] button.dropdown-item[data-notebook-id='#{notebook.id}']", text: /Research notebook/
    assert_select ".notepad-entry-move-modal .modal-content[data-controller='move-destination'][data-move-destination-notebooks-value*='Interviews']"
    assert_select "[data-move-destination-target='chapterMenu'] button.dropdown-item.disabled", text: /Choose a notebook first/
    assert_select ".notepad-entry-move-modal [data-bs-toggle='dropdown']", count: 2
    assert_select "button.notepad-entry-move-modal__save-button", text: /Move to notebook chapter/
    assert_select ".notepad-entry-move-shell button[name='intent'][value='move_to_notebook']", count: 0
    assert_select ".notepad-entry-move-modal button[name='intent'][value='move_to_notebook'][data-action='click->move-destination#commitSelection']", text: /Move to notebook chapter/

    patch notepad_entry_path(entry), params: {
      authenticity_token: authenticity_token_for(notepad_entry_path(entry)),
      intent: "move_to_notebook",
      move_to_chapter_id: chapter.id,
      notepad_entry: {
        title: "Moved from notepad",
        notes: "Move this into the project notebook with its photo.",
        entry_date: Date.new(2026, 4, 11)
      }
    }

    page = chapter.pages.order(:created_at).last

    assert_redirected_to notebook_chapter_page_path(notebook, chapter, page)
    assert_nil user.notepad_entries.find_by(id: entry.id)
    assert_equal "Moved from notepad - Page 1", page.title
    assert_equal "Move this into the project notebook with its photo.", page.notes
    assert_equal Date.new(2026, 4, 11), page.captured_on
    assert_equal 1, page.photos.count
  end

  test "moving a notepad entry into a notebook chapter preserves its to-do list and reminders" do
    user = User.create!(
      email: "todo-mover@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )

    notebook = user.notebooks.create!(
      title: "Research notebook",
      description: "Project notes",
      status: :active
    )
    chapter = notebook.chapters.create!(title: "Interviews", description: "Conversation logs")

    entry = user.notepad_entries.create!(
      title: "Checklist capture",
      notes: "Temporary notes",
      entry_date: Date.new(2026, 4, 10)
    )
    todo_list = entry.create_todo_list!(enabled: true, hide_completed: true)
    first_item = todo_list.todo_items.create!(content: "Follow up with supplier")
    todo_list.todo_items.create!(content: "Share recap")
    reminder = user.reminders.create!(
      title: "Follow up reminder",
      fire_at: 1.day.from_now,
      target: first_item
    )

    sign_in_browser_user(user)
    get edit_notepad_entry_path(entry)

    patch notepad_entry_path(entry), params: {
      authenticity_token: authenticity_token_for(notepad_entry_path(entry)),
      intent: "move_to_notebook",
      move_to_chapter_id: chapter.id,
      notepad_entry: {
        title: "Checklist capture",
        notes: "",
        entry_date: Date.new(2026, 4, 11),
        todo_list_enabled: "true",
        todo_list_hide_completed: "true"
      }
    }

    page = chapter.pages.order(:created_at).last

    assert_redirected_to notebook_chapter_page_path(notebook, chapter, page)
    assert_nil user.notepad_entries.find_by(id: entry.id)
    assert page.todo_list.enabled?
    assert page.todo_list.hide_completed?
    assert_equal ["Share recap", "Follow up with supplier"], page.todo_list.todo_items.ordered.pluck(:content)
    assert_equal page, reminder.reload.target.todo_list.page
  end

  test "user can move a notebook page into another notebook chapter from the show page" do
    user = User.create!(
      email: "page-mover@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )

    source_notebook = user.notebooks.create!(
      title: "Operations",
      description: "Working pages",
      status: :active
    )
    source_chapter = source_notebook.chapters.create!(title: "Active work", description: "Current queue")
    destination_notebook = user.notebooks.create!(
      title: "Archive",
      description: "Moved pages",
      status: :active
    )
    destination_chapter = destination_notebook.chapters.create!(title: "Done", description: "Archive queue")

    page = source_chapter.pages.create!(
      title: "Strategy notes",
      notes: "Move this into the archive chapter.",
      captured_on: Date.new(2026, 4, 10)
    )
    remaining_page = source_chapter.pages.create!(
      title: "Follow-up notes",
      notes: "Stay in the source chapter.",
      captured_on: Date.new(2026, 4, 11)
    )
    destination_existing_page = destination_chapter.pages.create!(
      title: "Archived brief",
      notes: "Already in the destination chapter.",
      captured_on: Date.new(2026, 4, 9)
    )

    sign_in_browser_user(user)

    get notebook_chapter_page_path(source_notebook, source_chapter, page)

    assert_response :success
    assert_select ".page-move-shell", count: 1
    move_form_id = ActionView::RecordIdentifier.dom_id(page, :move_form)
    move_modal_id = ActionView::RecordIdentifier.dom_id(page, :move_destination_modal)
    assert_select ".page-move-shell button[name='intent'][value='move_to_notebook'][form='#{move_form_id}']", count: 0
    assert_select "##{move_modal_id} button[name='intent'][value='move_to_notebook'][form='#{move_form_id}'][data-action='click->move-destination#commitSelection']", text: /Move to notebook chapter/

    patch notebook_chapter_page_path(source_notebook, source_chapter, page), params: {
      authenticity_token: authenticity_token_for(notebook_chapter_page_path(source_notebook, source_chapter, page)),
      intent: "move_to_notebook",
      move_to_chapter_id: destination_chapter.id
    }

    assert_redirected_to notebook_chapter_page_path(destination_notebook, destination_chapter, page)

    page.reload
    remaining_page.reload
    destination_existing_page.reload

    assert_equal destination_chapter, page.chapter
    assert_equal 2, page.position
    assert_equal "Strategy notes - Page 2", page.title
    assert_equal [remaining_page.id], source_chapter.pages.ordered.pluck(:id)
    assert_equal 1, remaining_page.position
    assert_equal "Follow-up notes - Page 1", remaining_page.title
    assert_equal [destination_existing_page.id, page.id], destination_chapter.pages.ordered.pluck(:id)
  end

  test "user can move a notebook page into notepad from the show page" do
    user = User.create!(
      email: "page-to-notepad@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )

    notebook = user.notebooks.create!(
      title: "Operations",
      description: "Working pages",
      status: :active
    )
    chapter = notebook.chapters.create!(title: "Active work", description: "Current queue")
    page = chapter.pages.create!(
      title: "Strategy notes",
      notes: "Move this into notepad.",
      captured_on: Date.new(2026, 4, 12)
    )
    remaining_page = chapter.pages.create!(
      title: "Follow-up notes",
      notes: "Stay in the chapter.",
      captured_on: Date.new(2026, 4, 13)
    )
    page.photos.attach(
      io: StringIO.new("page image bytes"),
      filename: "page.jpg",
      content_type: "image/jpeg"
    )
    voice_note = page.voice_notes.new(
      duration_seconds: 18,
      recorded_at: Time.zone.parse("2026-04-12T09:15:00Z"),
      byte_size: 128,
      mime_type: "audio/webm"
    )
    voice_note.audio.attach(
      io: StringIO.new("voice bytes"),
      filename: "page-note.webm",
      content_type: "audio/webm"
    )
    voice_note.save!
    todo_list = page.create_todo_list!(enabled: true, hide_completed: true)
    first_item = todo_list.todo_items.create!(content: "Share summary")
    todo_list.todo_items.create!(content: "Archive notes")
    reminder = user.reminders.create!(
      title: "Share summary reminder",
      fire_at: 1.day.from_now,
      target: first_item
    )
    scanned_document = page.scanned_documents.new(
      user: user,
      title: "Receipt"
    )
    scanned_document.enhanced_image.attach(
      io: StringIO.new("jpeg-bytes"),
      filename: "receipt.jpg",
      content_type: "image/jpeg"
    )
    scanned_document.document_pdf.attach(
      io: StringIO.new(tiny_pdf_binary),
      filename: "receipt.pdf",
      content_type: "application/pdf"
    )
    scanned_document.save!

    sign_in_browser_user(user)

    get notebook_chapter_page_path(notebook, chapter, page)

    assert_response :success
    assert_select "button[name='intent'][value='move_to_notepad']", text: /Move to notepad/

    assert_difference -> { user.notepad_entries.count }, +1 do
      patch notebook_chapter_page_path(notebook, chapter, page), params: {
        authenticity_token: authenticity_token_for(notebook_chapter_page_path(notebook, chapter, page)),
        intent: "move_to_notepad"
      }
    end

    entry = user.notepad_entries.order(:created_at).last

    assert_redirected_to notepad_entry_path(entry)
    assert_nil Page.find_by(id: page.id)

    entry.reload
    remaining_page.reload
    reminder.reload
    scanned_document.reload

    assert_equal "Strategy notes", entry.title
    assert_equal "Move this into notepad.", entry.plain_notes
    assert_equal Date.new(2026, 4, 12), entry.entry_date
    assert_equal 1, entry.photos.count
    assert_equal entry, voice_note.reload.notepad_entry
    assert_nil voice_note.page
    assert entry.todo_list.enabled?
    assert entry.todo_list.hide_completed?
    assert_equal ["Archive notes", "Share summary"], entry.todo_list.todo_items.ordered.pluck(:content)
    assert_equal entry, reminder.target.todo_list.notepad_entry
    assert_equal entry, scanned_document.notepad_entry
    assert_nil scanned_document.page
    assert_equal [remaining_page.id], chapter.pages.ordered.pluck(:id)
    assert_equal 1, remaining_page.position
    assert_equal "Follow-up notes - Page 1", remaining_page.title
  end

  test "notebooks index supports search and six-per-page pagination for current and archived views" do
    user = User.create!(
      email: "reader@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )

    7.times do |index|
      notebook = user.notebooks.create!(
        title: "Current notebook #{index + 1}",
        description: "Current description #{index + 1}",
        status: :active
      )
      notebook.update_columns(created_at: (7 - index).hours.ago, updated_at: (7 - index).hours.ago)
    end

    7.times do |index|
      notebook = user.notebooks.create!(
        title: "Archived notebook #{index + 1}",
        description: "Archived description #{index + 1}",
        status: :archived
      )
      notebook.update_columns(created_at: (7 - index).days.ago, updated_at: (7 - index).days.ago)
    end

    matching_current = user.notebooks.create!(
      title: "Alpha notebook",
      description: "Quarterly planning hub",
      status: :active
    )
    matching_current.chapters.create!(title: "Alpha chapter", description: "Planning")

    matching_archived = user.notebooks.create!(
      title: "Dormant workspace",
      description: "Archived delivery notes",
      status: :archived
    )
    matching_archived.chapters.create!(title: "Legacy alpha notes", description: "Archive reference")

    sign_in_browser_user(user)

    get notebooks_path

    assert_response :success
    assert_select ".wrapper.wrapper-content[data-controller='live-search'][data-live-search-delay-value='220']"
    assert_select "form.notebook-index-search-form[data-live-search-target='form']"
    assert_select "input.notebook-index-search-input[data-live-search-target='field']"
    assert_select "#current-notebooks-content .notebook-list-card", 6
    assert_select "#current-notebooks-content .notebook-list-card__title", text: "Current notebook 1", count: 0
    assert_select "#current-notebooks-content a.notebook-section-pagination__button", text: /Next/

    get notebooks_path(page: 2)

    assert_response :success
    assert_select "#current-notebooks-content .notebook-list-card", 2
    assert_select "#current-notebooks-content .notebook-list-card__title", text: "Current notebook 1"
    assert_select "#current-notebooks-content .notebook-list-card__title", text: "Current notebook 2"

    get notebooks_path(q: "Alpha")

    assert_response :success
    assert_select "#current-notebooks-content .notebook-list-card", 1
    assert_select "#current-notebooks-content .notebook-list-card__title", text: "Alpha notebook"

    get notebooks_path(scope: "archived")

    assert_response :success
    assert_select "#archived-notebooks-content .notebook-list-card", 6
    assert_select "#archived-notebooks-content a.notebook-section-pagination__button", text: /Next/

    get notebooks_path(scope: "archived", q: "alpha")

    assert_response :success
    assert_select "#archived-notebooks-content .notebook-list-card", 1
    assert_select "#archived-notebooks-content .notebook-list-card__title", text: "Dormant workspace"
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

  def audio_upload(filename:, content_type:, contents:)
    tempfile = Tempfile.new([File.basename(filename, ".*"), File.extname(filename)])
    tempfile.binmode
    tempfile.write(contents)
    tempfile.rewind

    Rack::Test::UploadedFile.new(
      tempfile.path,
      content_type,
      original_filename: filename
    )
  end

  def scanned_document_payload(title:, text: nil)
    {
      title: title,
      enhancement_filter: "auto",
      tags: ["receipt"].to_json,
      image_data: tiny_jpeg_data_url,
      pdf_data: tiny_pdf_data_url
    }
  end

  def tiny_jpeg_data_url
    "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQAAAQABAAD/2wCEAAkGBxAQEBUQEBAVFhUVFRUVFRUVFRUVFRUVFRUWFhUVFRUYHSggGBolHRUVITEhJSkrLi4uFx8zODMsNygtLisBCgoKDg0OGxAQGi0lHyUtLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLf/AABEIAAEAAQMBEQACEQEDEQH/xAAXAAADAQAAAAAAAAAAAAAAAAAAAQMC/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAwDAQACEAMQAAAB6AAAAP/EABQQAQAAAAAAAAAAAAAAAAAAADD/2gAIAQEAAT8Af//EABQRAQAAAAAAAAAAAAAAAAAAADD/2gAIAQIBAT8Af//EABQRAQAAAAAAAAAAAAAAAAAAADD/2gAIAQMBAT8Af//Z"
  end

  def tiny_pdf_binary
    "%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF\n".b
  end

  def tiny_pdf_data_url
    "data:application/pdf;base64,#{Base64.strict_encode64(tiny_pdf_binary)}"
  end
end
