require "test_helper"

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
end
