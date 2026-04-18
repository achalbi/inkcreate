require "test_helper"
require "tempfile"

class PageEnhancementsFlowTest < ActionDispatch::IntegrationTest
  test "dashboard shows upcoming reminders in time order" do
    user = build_user(email: "reminders-home@example.com")
    later = user.reminders.create!(
      title: "Follow up tomorrow",
      fire_at: 1.day.from_now,
      status: :pending
    )
    sooner = user.reminders.create!(
      title: "Quick nudge",
      fire_at: 15.minutes.from_now,
      status: :pending
    )
    user.reminders.create!(
      title: "Old dismissed reminder",
      fire_at: 2.days.ago,
      status: :dismissed
    )

    sign_in_browser_user(user)
    follow_redirect!

    assert_response :success
    assert_select "h5", text: "Upcoming reminders"
    assert_select ".notebook-list-card__title", text: sooner.title
    assert_select ".notebook-list-card__title", text: later.title
    assert_select ".notebook-list-card__title", text: "Old dismissed reminder", count: 0
    assert_operator response.body.index(sooner.title), :<, response.body.index(later.title)
    assert_select "form[action='#{reminders_path}']"
  end

  test "user can create a standalone reminder from the dashboard form" do
    user = build_user(email: "new-reminder@example.com")

    sign_in_browser_user(user)
    follow_redirect!

    post reminders_path, params: {
      authenticity_token: authenticity_token_for(reminders_path),
      reminder: {
        title: "Review audio notes",
        note: "Open the modal reminder path",
        fire_at_local: 2.hours.from_now.strftime("%Y-%m-%dT%H:%M")
      }
    }

    reminder = user.reminders.find_by!(title: "Review audio notes")

    assert_redirected_to reminders_path
    assert reminder.standalone?
    assert_equal "Open the modal reminder path", reminder.note
  end

  test "creating a reminder twice for the same todo item updates the existing reminder" do
    user = build_user(email: "todo-reminder-upsert@example.com")
    notebook = user.notebooks.create!(title: "Operations", status: :active)
    chapter = notebook.chapters.create!(title: "Launch", description: "Checklist")
    page = chapter.pages.create!(title: "Launch tasks", notes: "Prep items")
    todo_list = page.create_todo_list!(enabled: true, hide_completed: false)
    todo_item = todo_list.todo_items.create!(content: "Confirm venue")

    sign_in_browser_user(user)

    get notebook_chapter_page_path(notebook, chapter, page)
    token = authenticity_token_for(reminders_path)

    post reminders_path, params: {
      authenticity_token: token,
      reminder: {
        title: "Venue reminder",
        note: "Call the venue manager.",
        fire_at_local: 2.hours.from_now.strftime("%Y-%m-%dT%H:%M"),
        target_type: "TodoItem",
        target_id: todo_item.id
      }
    }

    assert_redirected_to notebook_chapter_page_path(notebook, chapter, page)
    assert_equal 1, user.reminders.where(target: todo_item).count

    post reminders_path, params: {
      authenticity_token: token,
      reminder: {
        title: "Venue reminder updated",
        note: "Confirm AV and seating too.",
        fire_at_local: 3.hours.from_now.strftime("%Y-%m-%dT%H:%M"),
        target_type: "TodoItem",
        target_id: todo_item.id
      }
    }

    reminder = user.reminders.find_by!(target: todo_item)

    assert_redirected_to notebook_chapter_page_path(notebook, chapter, page)
    assert_equal 1, user.reminders.where(target: todo_item).count
    assert_equal "Venue reminder updated", reminder.title
    assert_equal "Confirm AV and seating too.", reminder.note
  end

  test "user can create a page with only a voice note upload" do
    user = build_user(email: "voice-note-page@example.com")
    notebook = user.notebooks.create!(title: "Field notes", status: :active)
    chapter = notebook.chapters.create!(title: "Visits", description: "Site walk")

    sign_in_browser_user(user)

    get new_notebook_chapter_page_path(notebook, chapter)

    upload = nil
    upload = audio_upload(filename: "sample-note.webm", content_type: "audio/webm", contents: "voice-note-bytes")

    assert_difference -> { chapter.pages.count }, +1 do
      post notebook_chapter_pages_path(notebook, chapter), params: {
        authenticity_token: authenticity_token_for(notebook_chapter_pages_path(notebook, chapter)),
        page: {
          title: "",
          notes: "",
          captured_on: Date.current,
          voice_note_uploads: [upload],
          voice_note_duration_seconds: ["31"],
          voice_note_recorded_ats: [Time.current.iso8601]
        }
      }
    end

    entry_page = chapter.pages.order(:created_at).last

    assert_redirected_to notebook_chapter_page_path(notebook, chapter, entry_page)
    assert_equal 1, entry_page.voice_notes.count
    assert entry_page.voice_notes.first.audio.attached?
    assert_equal 31, entry_page.voice_notes.first.duration_seconds
  ensure
    upload&.tempfile&.close!
  end

  test "user can create a page with only a location check-in" do
    user = build_user(email: "location-page@example.com")
    notebook = user.notebooks.create!(title: "Field notes", status: :active)
    chapter = notebook.chapters.create!(title: "Visits", description: "Site walk")

    sign_in_browser_user(user)

    assert_difference -> { chapter.pages.count }, +1 do
      post notebook_chapter_pages_path(notebook, chapter), params: {
        authenticity_token: authenticity_token_for(notebook_chapter_pages_path(notebook, chapter)),
        page: {
          title: "",
          notes: "",
          captured_on: Date.current,
          locations_json: [
            {
              name: "Bengaluru office",
              address: "Bengaluru office, MG Road, Bengaluru, Karnataka, India",
              latitude: "12.975300",
              longitude: "77.605000",
              source: "search"
            },
            {
              name: "Client site",
              address: "Client site, Indiranagar, Bengaluru, Karnataka, India",
              latitude: "12.978400",
              longitude: "77.640800",
              source: "manual"
            }
          ].to_json
        }
      }
    end

    entry_page = chapter.pages.order(:created_at).last

    assert_redirected_to notebook_chapter_page_path(notebook, chapter, entry_page)
    assert_equal 2, entry_page.location_count
    assert_equal "Bengaluru office", entry_page.location_label
    assert_equal "Bengaluru office - Page 1", entry_page.display_title

    follow_redirect!

    assert_response :success
    assert_select ".location-picker__summary-count", text: "2 locations saved"
    assert_select ".location-picker__summary-title", text: "Bengaluru office"
    assert_select ".location-picker__summary-title", text: "Client site"
    assert_no_match "No content yet.", response.body
  end

  test "user can update locations from the page show form payload" do
    user = build_user(email: "page-show-location-update@example.com")
    notebook = user.notebooks.create!(title: "Field notes", status: :active)
    chapter = notebook.chapters.create!(title: "Visits", description: "Site walk")
    page = chapter.pages.create!(
      title: "Show form target",
      notes: "Keep these notes while adding a place.",
      captured_on: Date.new(2026, 4, 18)
    )

    sign_in_browser_user(user)

    get notebook_chapter_page_path(notebook, chapter, page)

    patch notebook_chapter_page_path(notebook, chapter, page), params: {
      authenticity_token: authenticity_token_for(notebook_chapter_page_path(notebook, chapter, page)),
      page: {
        title: page.title,
        notes: page.notes.to_s,
        captured_on: page.captured_on,
        locations_json: [
          {
            name: "Client office",
            address: "Client office, MG Road, Bengaluru, Karnataka, India",
            latitude: "12.975300",
            longitude: "77.605000",
            source: "search"
          }
        ].to_json
      }
    }

    assert_redirected_to notebook_chapter_page_path(notebook, chapter, page)
    assert_equal 1, page.reload.location_count
    assert_equal "Client office", page.location_label
    assert_equal "Keep these notes while adding a place.", page.plain_notes
  end

  test "user can create a page with only contacts" do
    user = build_user(email: "contact-page@example.com")
    notebook = user.notebooks.create!(title: "Field notes", status: :active)
    chapter = notebook.chapters.create!(title: "Visits", description: "Site walk")

    sign_in_browser_user(user)

    assert_difference -> { chapter.pages.count }, +1 do
      post notebook_chapter_pages_path(notebook, chapter), params: {
        authenticity_token: authenticity_token_for(notebook_chapter_pages_path(notebook, chapter)),
        page: {
          title: "",
          notes: "",
          captured_on: Date.current,
          contacts_json: [
            {
              name: "Ada Lovelace",
              primary_phone: "+1 555 010 2000",
              secondary_phone: "+1 555 010 3000",
              email: "ada@example.com",
              website: "example.com"
            },
            {
              name: "Grace Hopper",
              primary_phone: "+1 555 010 4000",
              email: "grace@example.com",
              website: "gracehopper.dev"
            }
          ].to_json
        }
      }
    end

    entry_page = chapter.pages.order(:created_at).last

    assert_redirected_to notebook_chapter_page_path(notebook, chapter, entry_page)
    assert_equal 2, entry_page.contact_count
    assert_equal "Ada Lovelace", entry_page.contact_label
    assert_equal "Ada Lovelace - Page 1", entry_page.display_title

    follow_redirect!

    assert_response :success
    assert_select ".contact-section__summary-count", text: "2 contacts saved"
    assert_select ".contact-section__summary-title", text: "Ada Lovelace"
    assert_select ".contact-section__summary-title", text: "Grace Hopper"
    assert_no_match "No content yet.", response.body
  end

  test "user can update contacts from the page show form payload" do
    user = build_user(email: "page-show-contact-update@example.com")
    notebook = user.notebooks.create!(title: "Field notes", status: :active)
    chapter = notebook.chapters.create!(title: "Visits", description: "Site walk")
    page = chapter.pages.create!(
      title: "Show form target",
      notes: "Keep these notes while adding a contact.",
      captured_on: Date.new(2026, 4, 18)
    )

    sign_in_browser_user(user)

    get notebook_chapter_page_path(notebook, chapter, page)

    patch notebook_chapter_page_path(notebook, chapter, page), params: {
      authenticity_token: authenticity_token_for(notebook_chapter_page_path(notebook, chapter, page)),
      page: {
        title: page.title,
        notes: page.notes.to_s,
        captured_on: page.captured_on,
        contacts_json: [
          {
            name: "Grace Hopper",
            primary_phone: "+1 555 010 4000",
            email: "grace@example.com",
            website: "gracehopper.dev"
          }
        ].to_json
      }
    }

    assert_redirected_to notebook_chapter_page_path(notebook, chapter, page)
    assert_equal 1, page.reload.contact_count
    assert_equal "Grace Hopper", page.contact_label
    assert_equal "Keep these notes while adding a contact.", page.plain_notes
  end

  test "saving the same page voice note twice only creates one record" do
    user = build_user(email: "page-voice-dedupe@example.com")
    notebook = user.notebooks.create!(title: "Field notes", status: :active)
    chapter = notebook.chapters.create!(title: "Visits", description: "Site walk")
    page = chapter.pages.create!(title: "Capture target", notes: "Existing page")

    sign_in_browser_user(user)

    recorded_at = Time.zone.parse("2026-04-15T09:30:00Z").iso8601
    first_upload = audio_upload(filename: "duplicate-page-note.webm", content_type: "audio/webm", contents: "voice-note-bytes")
    second_upload = audio_upload(filename: "duplicate-page-note.webm", content_type: "audio/webm", contents: "voice-note-bytes")

    assert_difference -> { page.voice_notes.count }, +1 do
      post notebook_chapter_page_voice_notes_path(notebook, chapter, page), params: {
        authenticity_token: authenticity_token_for(notebook_chapter_page_voice_notes_path(notebook, chapter, page)),
        voice_note: {
          audio: first_upload,
          duration_seconds: "31",
          recorded_at: recorded_at
        }
      }
    end

    assert_redirected_to notebook_chapter_page_path(notebook, chapter, page)

    assert_no_difference -> { page.reload.voice_notes.count } do
      post notebook_chapter_page_voice_notes_path(notebook, chapter, page), params: {
        authenticity_token: authenticity_token_for(notebook_chapter_page_voice_notes_path(notebook, chapter, page)),
        voice_note: {
          audio: second_upload,
          duration_seconds: "31",
          recorded_at: recorded_at
        }
      }
    end

    assert_redirected_to notebook_chapter_page_path(notebook, chapter, page)
    assert_equal 1, page.reload.voice_notes.count
    assert page.voice_notes.first.audio.attached?
  ensure
    first_upload&.tempfile&.close!
    second_upload&.tempfile&.close!
  end

  test "user can create a page with only scanned documents" do
    user = build_user(email: "scanned-page@example.com")
    notebook = user.notebooks.create!(title: "Paper trail", status: :active)
    chapter = notebook.chapters.create!(title: "Receipts", description: "Captured scans")

    sign_in_browser_user(user)

    get new_notebook_chapter_page_path(notebook, chapter)

    assert_response :success
    assert_select "h5", text: "Scanned documents"
    assert_no_match "Web scan mode", response.body
    assert_no_match "Saved with this form", response.body

    assert_difference -> { chapter.pages.count }, +1 do
      post notebook_chapter_pages_path(notebook, chapter), params: {
        authenticity_token: authenticity_token_for(notebook_chapter_pages_path(notebook, chapter)),
        page: {
          title: "",
          notes: "",
          captured_on: Date.current,
          pending_scanned_documents_json: [scanned_document_payload(title: "Receipt", text: "Total: 42.00")].to_json
        }
      }
    end

    entry_page = chapter.pages.order(:created_at).last

    assert_redirected_to notebook_chapter_page_path(notebook, chapter, entry_page)
    assert_equal 1, entry_page.scanned_documents.count
    assert entry_page.scanned_documents.first.enhanced_image.attached?
    assert entry_page.scanned_documents.first.document_pdf.attached?
    assert_equal tiny_pdf_binary, entry_page.scanned_documents.first.document_pdf.download
    assert_nil entry_page.scanned_documents.first.extracted_text
  end

  test "page scanned documents auto-title duplicates gain a numeric suffix" do
    user = build_user(email: "page-scan-title-suffix@example.com")
    notebook = user.notebooks.create!(title: "Paper trail", status: :active)
    chapter = notebook.chapters.create!(title: "Receipts", description: "Captured scans")
    auto_title = "Scan — Apr 14, 2026 10:15:30"

    sign_in_browser_user(user)
    get new_notebook_chapter_page_path(notebook, chapter)

    assert_difference -> { chapter.pages.count }, +1 do
      post notebook_chapter_pages_path(notebook, chapter), params: {
        authenticity_token: authenticity_token_for(notebook_chapter_pages_path(notebook, chapter)),
        page: {
          title: "",
          notes: "",
          captured_on: Date.current,
          pending_scanned_documents_json: [
            scanned_document_payload(title: auto_title),
            scanned_document_payload(title: auto_title)
          ].to_json
        }
      }
    end

    entry_page = chapter.pages.order(:created_at).last
    assert_equal [auto_title, "#{auto_title} #2"], entry_page.scanned_documents.order(:created_at).pluck(:title)
  end

  test "user can run OCR on a saved page scan" do
    user = build_user(email: "page-scan-ocr@example.com")
    notebook = user.notebooks.create!(title: "Paper trail", status: :active)
    chapter = notebook.chapters.create!(title: "Receipts", description: "Captured scans")
    page = chapter.pages.create!(title: "Expense scans", notes: "April receipts")

    sign_in_browser_user(user)
    get notebook_chapter_page_path(notebook, chapter, page)

    assert_difference -> { page.scanned_documents.count }, +1 do
      post notebook_chapter_page_scanned_documents_path(notebook, chapter, page), params: {
        authenticity_token: authenticity_token_for(notebook_chapter_page_scanned_documents_path(notebook, chapter, page)),
        scanned_document: scanned_document_payload(title: "Receipt")
      }
    end

    scanned_document = page.scanned_documents.order(:created_at).last
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
      post extract_text_notebook_chapter_page_scanned_document_path(notebook, chapter, page, scanned_document), params: {
        authenticity_token: authenticity_token_for(extract_text_notebook_chapter_page_scanned_document_path(notebook, chapter, page, scanned_document))
      }
    end

    assert_redirected_to notebook_chapter_page_path(notebook, chapter, page)
    scanned_document.reload
    assert_equal "Total: 42.00", scanned_document.extracted_text
    assert_equal "tesseract", scanned_document.ocr_engine
    assert_equal "eng", scanned_document.ocr_language
    assert_in_delta 88.0, scanned_document.ocr_confidence, 0.001

    follow_redirect!

    assert_response :success
    modal_id = ActionView::RecordIdentifier.dom_id(page, :scanned_document_ocr_modal)
    modal_frame_id = ActionView::RecordIdentifier.dom_id(page, :scanned_document_ocr_modal_frame)
    assert_select "form[action='#{extract_text_notebook_chapter_page_scanned_document_path(notebook, chapter, page, scanned_document)}'] button.sdoc-action-btn", text: /Re-run OCR/
    assert_select "##{modal_id}.sdoc-ocr-modal", count: 1
    assert_select "a.sdoc-action-btn[data-turbo-frame='#{modal_frame_id}'][href='#{show_text_notebook_chapter_page_scanned_document_path(notebook, chapter, page, scanned_document, frame_id: modal_frame_id)}']", text: /View OCR/
    assert_select "a.sdoc-action-btn[data-turbo-frame='#{modal_frame_id}'][href='#{edit_text_notebook_chapter_page_scanned_document_path(notebook, chapter, page, scanned_document, frame_id: modal_frame_id)}']", count: 0
    assert_select "a.sdoc-action-btn[data-turbo-frame='#{modal_frame_id}'][href='#{confirm_delete_text_notebook_chapter_page_scanned_document_path(notebook, chapter, page, scanned_document, frame_id: modal_frame_id)}']", count: 0
    assert_select ".sdoc-conf-badge.sdoc-conf-badge--high", text: /Confidence 88%/
    assert_select "a.sdoc-action-btn--icon[href='#{rails_blob_path(scanned_document.document_pdf, only_path: true, disposition: "attachment")}']", count: 1
    assert_select "form[action='#{notebook_chapter_page_scanned_document_path(notebook, chapter, page, scanned_document)}'] button.sdoc-action-btn--icon", count: 1
    assert_select ".sdoc-excerpt", count: 0

    get show_text_notebook_chapter_page_scanned_document_path(notebook, chapter, page, scanned_document), params: { frame_id: modal_frame_id }

    assert_response :success
    assert_match "View OCR text", response.body
    assert_match "Total: 42.00", response.body
    assert_select "a[href='#{edit_text_notebook_chapter_page_scanned_document_path(notebook, chapter, page, scanned_document, frame_id: modal_frame_id)}']", text: /Edit OCR/
    assert_select "a[href='#{confirm_delete_text_notebook_chapter_page_scanned_document_path(notebook, chapter, page, scanned_document, frame_id: modal_frame_id)}']", text: /Delete OCR/

    get edit_text_notebook_chapter_page_scanned_document_path(notebook, chapter, page, scanned_document), params: { frame_id: modal_frame_id }

    assert_response :success
    assert_select "textarea.sdoc-text-area", count: 1
    assert_select "a[href='#{show_text_notebook_chapter_page_scanned_document_path(notebook, chapter, page, scanned_document, frame_id: modal_frame_id)}']", text: /View OCR/
    assert_select "a[href='#{confirm_delete_text_notebook_chapter_page_scanned_document_path(notebook, chapter, page, scanned_document, frame_id: modal_frame_id)}']", text: /Delete OCR/
    assert_select "button[type='submit']", text: /Save changes/

    get confirm_delete_text_notebook_chapter_page_scanned_document_path(notebook, chapter, page, scanned_document), params: { frame_id: modal_frame_id }

    assert_response :success
    assert_match "Delete OCR text?", response.body
    assert_select "a[href='#{show_text_notebook_chapter_page_scanned_document_path(notebook, chapter, page, scanned_document, frame_id: modal_frame_id)}']", text: /View OCR/
    assert_select "form[action='#{delete_text_notebook_chapter_page_scanned_document_path(notebook, chapter, page, scanned_document)}'] button", text: /Delete OCR/
    delete_text_token = authenticity_token_for(delete_text_notebook_chapter_page_scanned_document_path(notebook, chapter, page, scanned_document))

    delete delete_text_notebook_chapter_page_scanned_document_path(notebook, chapter, page, scanned_document), params: {
      authenticity_token: delete_text_token
    }

    assert_redirected_to notebook_chapter_page_path(notebook, chapter, page)
    assert_nil scanned_document.reload.extracted_text
  end

  test "user can store a native OCR result on a saved page scan" do
    user = build_user(email: "page-scan-native-ocr@example.com")
    notebook = user.notebooks.create!(title: "Paper trail", status: :active)
    chapter = notebook.chapters.create!(title: "Receipts", description: "Captured scans")
    page = chapter.pages.create!(title: "Expense scans", notes: "April receipts")

    sign_in_browser_user(user)
    get notebook_chapter_page_path(notebook, chapter, page)

    assert_difference -> { page.scanned_documents.count }, +1 do
      post notebook_chapter_page_scanned_documents_path(notebook, chapter, page), params: {
        authenticity_token: authenticity_token_for(notebook_chapter_page_scanned_documents_path(notebook, chapter, page)),
        scanned_document: scanned_document_payload(title: "Invoice")
      }
    end

    scanned_document = page.scanned_documents.order(:created_at).last
    follow_redirect!

    post submit_ocr_result_notebook_chapter_page_scanned_document_path(notebook, chapter, page, scanned_document), params: {
      authenticity_token: authenticity_token_for(notebook_chapter_page_path(notebook, chapter, page)),
      ocr_result: {
        text: "Invoice Total 42.00",
        confidence: 0.91,
        language: "eng",
        engine: "google-ml"
      }
    }

    assert_redirected_to notebook_chapter_page_path(notebook, chapter, page)

    scanned_document.reload
    assert_equal "Invoice Total 42.00", scanned_document.extracted_text
    assert_equal "google-ml", scanned_document.ocr_engine
    assert_equal "eng", scanned_document.ocr_language
    assert_in_delta 91.0, scanned_document.ocr_confidence, 0.001
  end

  test "page voice note transcript can be submitted from the browser" do
    user = build_user(email: "page-voice-transcript@example.com")
    notebook = user.notebooks.create!(title: "Interviews", status: :active)
    chapter = notebook.chapters.create!(title: "Calls", description: "Recorded calls")
    page = chapter.pages.create!(title: "Customer call", notes: "Voice note capture")
    voice_note = page.voice_notes.new(
      duration_seconds: 64,
      recorded_at: Time.current.change(sec: 0),
      byte_size: 512,
      mime_type: "audio/webm"
    )
    voice_note.audio.attach(
      io: StringIO.new("voice"),
      filename: "call-note.webm",
      content_type: "audio/webm"
    )
    voice_note.save!

    sign_in_browser_user(user)
    get notebook_chapter_page_path(notebook, chapter, page)

    post submit_transcript_notebook_chapter_page_voice_note_path(notebook, chapter, page, voice_note), params: {
      authenticity_token: authenticity_token_for(notebook_chapter_page_path(notebook, chapter, page)),
      transcript_result: {
        text: "Action items reviewed and next steps confirmed."
      }
    }

    assert_redirected_to notebook_chapter_page_path(notebook, chapter, page)
    assert_equal "Action items reviewed and next steps confirmed.", voice_note.reload.transcript
  end

  test "user can create a page with only todo items" do
    user = build_user(email: "todo-page@example.com")
    notebook = user.notebooks.create!(title: "Operations", status: :active)
    chapter = notebook.chapters.create!(title: "Launch", description: "Checklist")

    sign_in_browser_user(user)

    get new_notebook_chapter_page_path(notebook, chapter)

    assert_difference -> { chapter.pages.count }, +1 do
      post notebook_chapter_pages_path(notebook, chapter), params: {
        authenticity_token: authenticity_token_for(notebook_chapter_pages_path(notebook, chapter)),
        page: {
          title: "",
          notes: "",
          captured_on: Date.current,
          todo_list_enabled: "true",
          todo_item_contents: ["Confirm venue", "Send recap"]
        }
      }
    end

    entry_page = chapter.pages.order(:created_at).last

    assert_redirected_to notebook_chapter_page_path(notebook, chapter, entry_page)
    assert entry_page.todo_list.enabled?
    assert_equal ["Send recap", "Confirm venue"], entry_page.todo_list.todo_items.ordered.pluck(:content)

    get notebook_chapter_page_path(notebook, chapter, entry_page)

    assert_operator response.body.index("Send recap"), :<, response.body.index("Confirm venue")
  end

  test "todo item reorder persists across reloads" do
    user = build_user(email: "todo-reorder@example.com")
    notebook = user.notebooks.create!(title: "Operations", status: :active)
    chapter = notebook.chapters.create!(title: "Launch", description: "Checklist")
    page = chapter.pages.create!(title: "Launch tasks", notes: "Prep items")
    todo_list = page.create_todo_list!(enabled: true, hide_completed: false)
    first_item = todo_list.todo_items.create!(content: "Confirm venue")
    second_item = todo_list.todo_items.create!(content: "Email recap")
    todo_list.todo_items.create!(content: "Pack microphones")

    sign_in_browser_user(user)

    get notebook_chapter_page_path(notebook, chapter, page)

    assert_operator response.body.index("Pack microphones"), :<, response.body.index("Email recap")
    assert_operator response.body.index("Email recap"), :<, response.body.index("Confirm venue")

    patch reorder_notebook_chapter_page_todo_item_path(notebook, chapter, page, first_item), params: {
      authenticity_token: authenticity_token_for(notebook_chapter_page_todo_items_path(notebook, chapter, page)),
      todo_item: { position: 1 }
    }

    assert_redirected_to notebook_chapter_page_path(notebook, chapter, page)
    assert_equal ["Confirm venue", "Pack microphones", "Email recap"], todo_list.reload.todo_items.ordered.pluck(:content)
    assert_equal 1, first_item.reload.position
    assert_equal 3, second_item.reload.position
    assert todo_list.reload.manually_reordered?

    get notebook_chapter_page_path(notebook, chapter, page)

    assert_operator response.body.index("Confirm venue"), :<, response.body.index("Pack microphones")
    assert_operator response.body.index("Pack microphones"), :<, response.body.index("Email recap")
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
