require "test_helper"
require "tempfile"

class GoogleDriveRecordExportTriggersTest < ActionDispatch::IntegrationTest
  test "page voice note mutations schedule record export" do
    user = build_user(email: "page-drive-export-voice@example.com")
    notebook = user.notebooks.create!(title: "Interviews", status: :active)
    chapter = notebook.chapters.create!(title: "Calls", description: "Recorded calls")
    page = chapter.pages.create!(title: "Customer call", notes: "Voice note capture")

    sign_in_browser_user(user)
    get notebook_chapter_page_path(notebook, chapter, page)
    token = authenticity_token_for(notebook_chapter_page_path(notebook, chapter, page))

    upload = audio_upload(filename: "page-note.webm", content_type: "audio/webm", contents: "voice-note-bytes")

    scheduled = capture_scheduled_records do
      post notebook_chapter_page_voice_notes_path(notebook, chapter, page), params: {
        authenticity_token: token,
        voice_note: {
          audio: upload,
          duration_seconds: "31",
          recorded_at: Time.current.iso8601
        }
      }

      voice_note = page.reload.voice_notes.order(:created_at).last

      post submit_transcript_notebook_chapter_page_voice_note_path(notebook, chapter, page, voice_note), params: {
        authenticity_token: token,
        transcript_result: { text: "Action items reviewed." }
      }

      delete notebook_chapter_page_voice_note_path(notebook, chapter, page, voice_note), params: {
        authenticity_token: token
      }
    end

    assert_equal [page.id, page.id, page.id], scheduled.map(&:id)
  ensure
    upload&.tempfile&.close!
  end

  test "page scanned document mutations schedule record export" do
    user = build_user(email: "page-drive-export-scan@example.com")
    notebook = user.notebooks.create!(title: "Paper trail", status: :active)
    chapter = notebook.chapters.create!(title: "Receipts", description: "Captured scans")
    page = chapter.pages.create!(title: "Expense scans", notes: "April receipts")

    sign_in_browser_user(user)
    get notebook_chapter_page_path(notebook, chapter, page)
    token = authenticity_token_for(notebook_chapter_page_path(notebook, chapter, page))

    scheduled = capture_scheduled_records do
      post notebook_chapter_page_scanned_documents_path(notebook, chapter, page), params: {
        authenticity_token: token,
        scanned_document: scanned_document_payload(title: "Receipt")
      }

      scanned_document = page.reload.scanned_documents.order(:created_at).last

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
          authenticity_token: token
        }
      end

      post submit_ocr_result_notebook_chapter_page_scanned_document_path(notebook, chapter, page, scanned_document), params: {
        authenticity_token: token,
        ocr_result: {
          text: "Invoice Total 42.00",
          confidence: 0.91,
          language: "eng",
          engine: "google-ml"
        }
      }

      delete notebook_chapter_page_scanned_document_path(notebook, chapter, page, scanned_document), params: {
        authenticity_token: token
      }
    end

    assert_equal [page.id, page.id, page.id, page.id], scheduled.map(&:id)
  end

  test "page todo list and item mutations schedule record export" do
    user = build_user(email: "page-drive-export-todo@example.com")
    notebook = user.notebooks.create!(title: "Operations", status: :active)
    chapter = notebook.chapters.create!(title: "Launch", description: "Checklist")
    page = chapter.pages.create!(title: "Launch tasks", notes: "Prep items")

    sign_in_browser_user(user)
    get notebook_chapter_page_path(notebook, chapter, page)
    token = authenticity_token_for(notebook_chapter_page_path(notebook, chapter, page))

    scheduled = capture_scheduled_records do
      post notebook_chapter_page_todo_list_path(notebook, chapter, page), params: {
        authenticity_token: token,
        todo_list: {
          enabled: "true",
          hide_completed: "false"
        }
      }

      post notebook_chapter_page_todo_items_path(notebook, chapter, page), params: {
        authenticity_token: token,
        todo_item: { content: "Confirm venue" }
      }

      first_item = page.reload.todo_list.todo_items.ordered.first

      post notebook_chapter_page_todo_items_path(notebook, chapter, page), params: {
        authenticity_token: token,
        todo_item: { content: "Send recap" }
      }

      page.reload
      first_item = page.todo_list.todo_items.find(first_item.id)
      second_item = page.todo_list.todo_items.ordered.find_by!(content: "Send recap")

      patch notebook_chapter_page_todo_item_path(notebook, chapter, page, first_item), params: {
        authenticity_token: token,
        todo_item: { content: "Confirm venue and AV" }
      }

      patch toggle_notebook_chapter_page_todo_item_path(notebook, chapter, page, first_item), params: {
        authenticity_token: token
      }

      patch reorder_notebook_chapter_page_todo_item_path(notebook, chapter, page, second_item), params: {
        authenticity_token: token,
        todo_item: { position: 1 }
      }

      delete notebook_chapter_page_todo_item_path(notebook, chapter, page, first_item), params: {
        authenticity_token: token
      }

      patch notebook_chapter_page_todo_list_path(notebook, chapter, page), params: {
        authenticity_token: token,
        todo_list: {
          enabled: "true",
          hide_completed: "true"
        }
      }
    end

    assert_equal [page.id] * 8, scheduled.map(&:id)
  end

  test "page reminder mutations schedule record export" do
    user = build_user(email: "page-drive-export-reminder@example.com")
    notebook = user.notebooks.create!(title: "Operations", status: :active)
    chapter = notebook.chapters.create!(title: "Launch", description: "Checklist")
    page = chapter.pages.create!(title: "Launch tasks", notes: "Prep items")
    todo_list = page.create_todo_list!(enabled: true, hide_completed: false)
    todo_item = todo_list.todo_items.create!(content: "Confirm venue")

    sign_in_browser_user(user)
    get notebook_chapter_page_path(notebook, chapter, page)
    token = authenticity_token_for(notebook_chapter_page_path(notebook, chapter, page))

    scheduled = capture_scheduled_records do
      post reminders_path, params: {
        authenticity_token: token,
        reminder: {
          title: "Page follow-up",
          fire_at_local: 1.hour.from_now.strftime("%Y-%m-%dT%H:%M"),
          target_type: "TodoItem",
          target_id: todo_item.id
        }
      }

      reminder = user.reminders.find_by!(target: todo_item)

      patch reminder_path(reminder), params: {
        authenticity_token: token,
        reminder: {
          title: "Page follow-up tomorrow",
          fire_at_local: 2.hours.from_now.strftime("%Y-%m-%dT%H:%M"),
          target_type: "TodoItem",
          target_id: todo_item.id
        }
      }

      delete reminder_path(reminder), params: {
        authenticity_token: token
      }
    end

    assert_equal [page.id, page.id, page.id], scheduled.map(&:id)
  end

  test "page create with embedded todo content only schedules one record export" do
    user = build_user(email: "page-drive-export-create@example.com")
    notebook = user.notebooks.create!(title: "Operations", status: :active)
    chapter = notebook.chapters.create!(title: "Launch", description: "Checklist")

    sign_in_browser_user(user)
    get new_notebook_chapter_page_path(notebook, chapter)
    token = authenticity_token_for(new_notebook_chapter_page_path(notebook, chapter))

    scheduled = capture_scheduled_records do
      post notebook_chapter_pages_path(notebook, chapter), params: {
        authenticity_token: token,
        page: {
          title: "Launch tasks",
          notes: "Prep items",
          captured_on: Date.current.iso8601,
          todo_list_enabled: "true",
          todo_list_hide_completed: "false",
          todo_item_contents: ["Confirm venue"]
        }
      }
    end

    page = chapter.pages.order(:created_at).last

    assert_equal [page.id], scheduled.map(&:id)
  end

  test "page updates and photo removal schedule record export" do
    user = build_user(email: "page-drive-export-update@example.com")
    notebook = user.notebooks.create!(title: "Operations", status: :active)
    chapter = notebook.chapters.create!(title: "Launch", description: "Checklist")
    page = chapter.pages.create!(title: "Launch tasks", notes: "Prep items")
    page.photos.attach(uploaded_image_blob("launch-board.jpg"))

    sign_in_browser_user(user)
    get notebook_chapter_page_path(notebook, chapter, page)
    token = authenticity_token_for(notebook_chapter_page_path(notebook, chapter, page))
    attachment = page.photos.attachments.first

    scheduled = capture_scheduled_records do
      patch notebook_chapter_page_path(notebook, chapter, page), params: {
        authenticity_token: token,
        page: {
          title: "Launch tasks revised",
          notes: "Prep items updated",
          captured_on: Date.current.iso8601,
          retained_photo_signed_ids: page.photos.blobs.map(&:signed_id)
        }
      }

      delete photo_notebook_chapter_page_path(notebook, chapter, page, attachment), params: {
        authenticity_token: token
      }
    end

    assert_equal [page.id, page.id], scheduled.map(&:id)
  end

  test "notepad scanned document mutations schedule record export" do
    user = build_user(email: "notepad-drive-export-scan@example.com")
    entry = user.notepad_entries.create!(
      title: "Inbox scans",
      notes: "Collect scans here.",
      entry_date: Date.current
    )

    sign_in_browser_user(user)
    get notepad_entry_path(entry)
    token = authenticity_token_for(notepad_entry_path(entry))

    scheduled = capture_scheduled_records do
      post notepad_entry_scanned_documents_path(entry), params: {
        authenticity_token: token,
        scanned_document: scanned_document_payload(title: "Receipt")
      }

      scanned_document = entry.reload.scanned_documents.order(:created_at).last

      ScannedDocuments::RunOcr.stub :new, ->(scanned_document:) {
        runner = Object.new
        runner.define_singleton_method(:call) do
          scanned_document.update!(
            extracted_text: "Total: 84.00",
            ocr_engine: "tesseract",
            ocr_language: "eng",
            ocr_confidence: 88
          )
        end
        runner
      } do
        post extract_text_notepad_entry_scanned_document_path(entry, scanned_document), params: {
          authenticity_token: token
        }
      end

      post submit_ocr_result_notepad_entry_scanned_document_path(entry, scanned_document), params: {
        authenticity_token: token,
        ocr_result: {
          text: "Invoice Total 84.00",
          confidence: 87,
          language: "eng",
          engine: "google-ml"
        }
      }

      delete notepad_entry_scanned_document_path(entry, scanned_document), params: {
        authenticity_token: token
      }
    end

    assert_equal [entry.id, entry.id, entry.id, entry.id], scheduled.map(&:id)
  end

  test "notepad updates, photo removal, and voice note mutations schedule record export" do
    user = build_user(email: "notepad-drive-export-update@example.com")
    entry = user.notepad_entries.create!(
      title: "Daily checklist",
      notes: "Tasks for today.",
      entry_date: Date.current
    )
    entry.photos.attach(uploaded_image_blob("daily-board.jpg"))

    sign_in_browser_user(user)
    get notepad_entry_path(entry)
    token = authenticity_token_for(notepad_entry_path(entry))
    attachment = entry.photos.attachments.first
    upload = audio_upload(filename: "notepad-note.webm", content_type: "audio/webm", contents: "voice-note-bytes")

    scheduled = capture_scheduled_records do
      patch notepad_entry_path(entry), params: {
        authenticity_token: token,
        notepad_entry: {
          title: "Daily checklist revised",
          notes: "Tasks updated.",
          entry_date: entry.entry_date.iso8601,
          retained_photo_signed_ids: entry.photos.blobs.map(&:signed_id)
        }
      }

      post notepad_entry_voice_notes_path(entry), params: {
        authenticity_token: token,
        voice_note: {
          audio: upload,
          duration_seconds: "31",
          recorded_at: Time.current.iso8601
        }
      }

      voice_note = entry.reload.voice_notes.order(:created_at).last

      post submit_transcript_notepad_entry_voice_note_path(entry, voice_note), params: {
        authenticity_token: token,
        transcript_result: { text: "Action items reviewed." }
      }

      delete notepad_entry_voice_note_path(entry, voice_note), params: {
        authenticity_token: token
      }

      delete photo_notepad_entry_path(entry, attachment), params: {
        authenticity_token: token
      }
    end

    assert_equal [entry.id, entry.id, entry.id, entry.id, entry.id], scheduled.map(&:id)
  ensure
    upload&.tempfile&.close!
  end

  test "notepad todo list and item mutations schedule record export" do
    user = build_user(email: "notepad-drive-export-todo@example.com")
    entry = user.notepad_entries.create!(
      title: "Daily checklist",
      notes: "Tasks for today.",
      entry_date: Date.current
    )

    sign_in_browser_user(user)
    get notepad_entry_path(entry)
    token = authenticity_token_for(notepad_entry_path(entry))

    scheduled = capture_scheduled_records do
      post notepad_entry_todo_list_path(entry), params: {
        authenticity_token: token,
        todo_list: {
          enabled: "true",
          hide_completed: "false"
        }
      }

      post notepad_entry_todo_items_path(entry), params: {
        authenticity_token: token,
        todo_item: { content: "Draft agenda" }
      }

      first_item = entry.reload.todo_list.todo_items.ordered.first

      post notepad_entry_todo_items_path(entry), params: {
        authenticity_token: token,
        todo_item: { content: "Send recap" }
      }

      entry.reload
      first_item = entry.todo_list.todo_items.find(first_item.id)
      second_item = entry.todo_list.todo_items.ordered.find_by!(content: "Send recap")

      patch notepad_entry_todo_item_path(entry, first_item), params: {
        authenticity_token: token,
        todo_item: { content: "Draft agenda and notes" }
      }

      patch toggle_notepad_entry_todo_item_path(entry, first_item), params: {
        authenticity_token: token
      }

      patch reorder_notepad_entry_todo_item_path(entry, second_item), params: {
        authenticity_token: token,
        todo_item: { position: 1 }
      }

      delete notepad_entry_todo_item_path(entry, first_item), params: {
        authenticity_token: token
      }

      patch notepad_entry_todo_list_path(entry), params: {
        authenticity_token: token,
        todo_list: {
          enabled: "true",
          hide_completed: "true"
        }
      }
    end

    assert_equal [entry.id] * 8, scheduled.map(&:id)
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

  def capture_scheduled_records
    scheduled = []

    Drive::ScheduleRecordExport.stub :new, ->(record:, **) {
      runner = Object.new
      runner.define_singleton_method(:call) { scheduled << record }
      runner
    } do
      yield
    end

    scheduled
  end

  def scanned_document_payload(title:)
    {
      title: title,
      enhancement_filter: "auto",
      tags: ["receipt"].to_json,
      image_data: tiny_jpeg_data_url,
      pdf_data: tiny_pdf_data_url
    }
  end

  def uploaded_image_blob(filename)
    {
      io: StringIO.new("jpeg-bytes"),
      filename: filename,
      content_type: "image/jpeg"
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
