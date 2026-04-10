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
    assert_select "select[data-move-destination-target='notebookSelect'] option", text: /Research notebook/
    assert_select ".notepad-entry-move-modal .modal-content[data-controller='move-destination'][data-move-destination-notebooks-value*='Interviews']"
    assert_select "select[data-move-destination-target='chapterSelect'] option", text: /Choose a chapter/
    assert_select "button.notepad-entry-move-modal__save-button", text: /Save destination/
    assert_select "button[name='intent'][value='move_to_notebook']", text: /Move to notebook chapter/

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
end
