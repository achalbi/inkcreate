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
    assert_equal ["Confirm venue", "Send recap"], entry_page.todo_list.todo_items.ordered.pluck(:content)
  end

  test "todo item reorder persists across reloads" do
    user = build_user(email: "todo-reorder@example.com")
    notebook = user.notebooks.create!(title: "Operations", status: :active)
    chapter = notebook.chapters.create!(title: "Launch", description: "Checklist")
    page = chapter.pages.create!(title: "Launch tasks", notes: "Prep items")
    todo_list = page.create_todo_list!(enabled: true, hide_completed: false)
    first_item = todo_list.todo_items.create!(content: "Confirm venue")
    todo_list.todo_items.create!(content: "Email recap")
    third_item = todo_list.todo_items.create!(content: "Pack microphones")

    sign_in_browser_user(user)

    get notebook_chapter_page_path(notebook, chapter, page)

    patch reorder_notebook_chapter_page_todo_item_path(notebook, chapter, page, third_item), params: {
      authenticity_token: authenticity_token_for(notebook_chapter_page_todo_list_path(notebook, chapter, page)),
      todo_item: { position: 1 }
    }

    assert_redirected_to notebook_chapter_page_path(notebook, chapter, page)
    assert_equal ["Pack microphones", "Confirm venue", "Email recap"], todo_list.reload.todo_items.ordered.pluck(:content)
    assert_equal 2, first_item.reload.position

    get notebook_chapter_page_path(notebook, chapter, page)

    assert_operator response.body.index("Pack microphones"), :<, response.body.index("Confirm venue")
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
end
