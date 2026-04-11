require "test_helper"
require "nokogiri"

class WorkspaceRoutesTest < ActionDispatch::IntegrationTest
  setup do
    User.create!(
      email: "bootstrap-admin@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :admin
    )

    @user = User.create!(
      email: "workspace@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )
    @project = @user.projects.create!(title: "Launch plan", description: "Reusable notebook planning")
    @daily_log = @user.daily_logs.create!(entry_date: Date.current, title: "Today")
    @notebook = @user.notebooks.create!(title: "Workspace notebook", status: :active)
    @chapter = @notebook.chapters.create!(title: "Chapter one", description: "Chapter notes")
    @page = @chapter.pages.create!(title: "Page one", notes: "Page details", captured_on: Date.current)
    @capture = @user.captures.create!(
      project: @project,
      daily_log: @daily_log,
      title: "Sprint retro",
      page_type: "single_line",
      original_filename: "retro.jpg",
      content_type: "image/jpeg",
      byte_size: 1024,
      storage_bucket: "test-bucket",
      storage_object_key: "users/#{@user.id}/uploads/test/retro.jpg",
      status: :uploaded,
      ocr_status: :not_started,
      ai_status: :not_started,
      backup_status: :local_only,
      sync_status: :synced
    )
  end

  test "signed in user can open the new workspace pages" do
    sign_in!

    [
      dashboard_path,
      capture_studio_path,
      inbox_path,
      projects_path,
      project_path(@project),
      daily_logs_path,
      daily_log_path(@daily_log),
      capture_path(@capture),
      search_page_path,
      tasks_path,
      reminders_path,
      library_path,
      settings_path,
      onboarding_path,
      install_path
    ].each do |path|
      get path
      assert_response :success, "Expected #{path} to render successfully"
    end

    get dashboard_path
    assert_select "#sidebar", count: 0
    assert_select "#topbar"
    assert_select "#page-loader"
    assert_select "link[href*='/inapp/page_loader.css?v=']"
    assert_select "link[href*='/inapp/inapp_workspace.css?v=']"
    assert_select "script[src*='/scripts/page_loader.js?v=']"
    assert_select "script[src*='/scripts/app.js?v=']"
  end

  test "legacy user without app settings can still open workspace pages" do
    @user.app_setting&.destroy!

    sign_in!

    get dashboard_path
    assert_response :success

    get settings_path
    assert_response :success

    assert @user.reload.app_setting.present?
  end

  test "workspace notice renders under the header section" do
    sign_in!

    get settings_path

    patch settings_backup_path, params: {
      authenticity_token: authenticity_token_for(settings_backup_path),
      app_setting: { backup_enabled: "false", backup_provider: "" }
    }

    follow_redirect!

    assert_response :success
    assert_select ".flash-banner.notice", text: /Backup settings updated/
  end

  test "settings page shows notification controls" do
    sign_in!

    get settings_path

    assert_response :success
    assert_select "h5", text: "App notifications"
    assert_select "[data-controller='device-push']", count: 1
    assert_select "[data-device-push-target='permissionStatus']", text: "Checking..."
    assert_select "[data-device-push-target='deviceStatus']", text: "Checking..."
    assert_select "button[data-action='device-push#enable']", text: "Enable on this device"
    assert_select "button[data-action='device-push#disable']", text: "Disable on this device"
  end

  test "settings page still renders when devices are unavailable in the schema" do
    sign_in!

    Device.stub(:schema_ready?, false) do
      get settings_path

      assert_response :success
      assert_select "h5", text: "App notifications"
      assert_select "button[data-action='device-push#enable'][disabled]"
      assert_select "button[data-action='device-push#disable'][disabled]"
    end
  end

  test "capture studio shows the voice note recorder when voice notes are available" do
    sign_in!

    get capture_studio_path

    assert_response :success
    assert_select ".quick-capture-voice-note-panel"
    assert_select "button[data-action='voice-recorder#start']", text: /Record voice note/
  end

  test "notepad edit page shows delete controls for existing voice notes" do
    sign_in!

    entry = @user.notepad_entries.create!(
      title: "Voice note entry",
      notes: "Has an audio note.",
      entry_date: Date.current
    )
    voice_note = entry.voice_notes.new(
      duration_seconds: 18,
      recorded_at: Time.current,
      byte_size: 128,
      mime_type: "audio/webm"
    )
    voice_note.audio.attach(
      io: StringIO.new("voice"),
      filename: "note.webm",
      content_type: "audio/webm"
    )
    voice_note.save!

    get edit_notepad_entry_path(entry)

    assert_response :success
    modal_id = ActionView::RecordIdentifier.dom_id(voice_note, :delete_confirm_modal)
    document = Nokogiri::HTML.parse(response.body)
    button = document.at_xpath("//button[@data-bs-toggle='modal' and @data-bs-target='##{modal_id}']")
    modal = document.at_xpath("//*[@id='#{modal_id}']")
    form = modal&.at_xpath(".//form[@method='post']")

    assert button.present?, "Expected delete trigger button for voice note modal"
    assert modal.present?, "Expected delete confirmation modal to be rendered"
    assert form.present?, "Expected delete confirmation form inside the voice note modal"
    assert_equal notepad_entry_voice_note_path(entry, voice_note), URI.parse(form["action"]).path
    assert_equal "delete", form.at_xpath(".//input[@name='_method']")&.[]("value")
  end

  test "page edit page shows delete controls for existing voice notes" do
    sign_in!

    voice_note = @page.voice_notes.new(
      duration_seconds: 24,
      recorded_at: Time.current,
      byte_size: 128,
      mime_type: "audio/webm"
    )
    voice_note.audio.attach(
      io: StringIO.new("voice"),
      filename: "page-note.webm",
      content_type: "audio/webm"
    )
    voice_note.save!

    get edit_notebook_chapter_page_path(@notebook, @chapter, @page)

    assert_response :success
    modal_id = ActionView::RecordIdentifier.dom_id(voice_note, :delete_confirm_modal)
    document = Nokogiri::HTML.parse(response.body)
    button = document.at_xpath("//button[@data-bs-toggle='modal' and @data-bs-target='##{modal_id}']")
    modal = document.at_xpath("//*[@id='#{modal_id}']")
    form = modal&.at_xpath(".//form[@method='post']")

    assert button.present?, "Expected delete trigger button for voice note modal"
    assert modal.present?, "Expected delete confirmation modal to be rendered"
    assert form.present?, "Expected delete confirmation form inside the voice note modal"
    assert_equal notebook_chapter_page_voice_note_path(@notebook, @chapter, @page, voice_note), URI.parse(form["action"]).path
    assert_equal "delete", form.at_xpath(".//input[@name='_method']")&.[]("value")
  end

  test "page edit page renders the live to-do list section for persisted pages" do
    sign_in!

    todo_list = @page.create_todo_list!(enabled: true, hide_completed: false)
    todo_list.todo_items.create!(content: "Pack charger", position: 1, completed: false)
    todo_list.todo_items.create!(content: "Review notes", position: 2, completed: true)

    get edit_notebook_chapter_page_path(@notebook, @chapter, @page)

    assert_response :success
    assert_select "form[action='#{notebook_chapter_page_todo_items_path(@notebook, @chapter, @page)}'] textarea[name='todo_item[content]']", count: 1
    assert_select ".todo-list-filters__button", text: "All"
    assert_select ".todo-list-filters__button", text: "Active"
    assert_select ".todo-list-filters__button", text: "Done"
    assert_select ".todo-list-item__input[title='Pack charger']", count: 1
    assert_select ".todo-list-item__input[title='Review notes']", count: 1
    assert_select ".todo-list-section__hint", text: /Drag to reorder/
    assert_no_match "Enable the checklist and queue items before saving this page.", response.body
    assert_no_match "Saved items on this page", response.body
  end

  test "notepad edit page renders the live to-do list section for persisted entries" do
    sign_in!

    entry = @user.notepad_entries.create!(
      title: "Checklist page",
      notes: "Needs the live checklist UI.",
      entry_date: Date.current
    )
    todo_list = entry.create_todo_list!(enabled: true, hide_completed: false)
    todo_list.todo_items.create!(content: "Pack charger", position: 1, completed: false)
    todo_list.todo_items.create!(content: "Review notes", position: 2, completed: true)

    get edit_notepad_entry_path(entry)

    assert_response :success
    assert_select "form[action='#{notepad_entry_todo_items_path(entry)}'] textarea[name='todo_item[content]']", count: 1
    assert_select ".todo-list-filters__button", text: "All"
    assert_select ".todo-list-filters__button", text: "Active"
    assert_select ".todo-list-filters__button", text: "Done"
    assert_select ".todo-list-item__input[title='Pack charger']", count: 1
    assert_select ".todo-list-item__input[title='Review notes']", count: 1
    assert_select ".todo-list-section__hint", text: /Drag to reorder/
    assert_no_match "Enable the checklist and queue items before saving this page.", response.body
    assert_no_match "Saved items on this page", response.body
    assert_operator response.body.index("To-do list"), :<, response.body.index("Move to notebook")
  end

  test "page overview shows voice note and to-do progress labels" do
    sign_in!

    page_voice_note = @page.voice_notes.new(
      duration_seconds: 24,
      recorded_at: Time.current,
      byte_size: 128,
      mime_type: "audio/webm"
    )
    page_voice_note.audio.attach(
      io: StringIO.new("voice"),
      filename: "page-note.webm",
      content_type: "audio/webm"
    )
    page_voice_note.save!

    page_todo_list = @page.create_todo_list!(enabled: true, hide_completed: false)
    page_todo_list.todo_items.create!(content: "Pack charger", position: 1, completed: true)
    page_todo_list.todo_items.create!(content: "Share notes", position: 2, completed: false)

    entry = @user.notepad_entries.create!(
      title: "Voice note entry",
      notes: "Has overview chips.",
      entry_date: Date.current
    )
    entry_voice_note = entry.voice_notes.new(
      duration_seconds: 18,
      recorded_at: Time.current,
      byte_size: 128,
      mime_type: "audio/webm"
    )
    entry_voice_note.audio.attach(
      io: StringIO.new("voice"),
      filename: "entry-note.webm",
      content_type: "audio/webm"
    )
    entry_voice_note.save!

    entry_todo_list = entry.create_todo_list!(enabled: true, hide_completed: false)
    entry_todo_list.todo_items.create!(content: "Review audio", position: 1, completed: true)
    entry_todo_list.todo_items.create!(content: "Follow up", position: 2, completed: false)

    get notebook_chapter_page_path(@notebook, @chapter, @page)

    assert_response :success
    assert_match "1 voice note", response.body
    assert_match "1/2 to-dos", response.body

    get notepad_entry_path(entry)

    assert_response :success
    assert_match "1 voice note", response.body
    assert_match "1/2 to-dos", response.body
  end

  test "page and notepad photo galleries expose inline photo actions on show pages" do
    sign_in!

    @page.photos.attach(
      io: StringIO.new("page photo"),
      filename: "page-photo.jpg",
      content_type: "image/jpeg"
    )
    page_attachment = @page.photos.attachments.last

    entry = @user.notepad_entries.create!(
      title: "Photo entry",
      notes: "Has gallery actions.",
      entry_date: Date.current
    )
    entry.photos.attach(
      io: StringIO.new("entry photo"),
      filename: "entry-photo.jpg",
      content_type: "image/jpeg"
    )
    entry_attachment = entry.photos.attachments.last

    get notebook_chapter_page_path(@notebook, @chapter, @page)

    assert_response :success
    assert_no_match "Manage photos", response.body
    assert_select ".detail-photo-gallery-actions-form", count: 1
    assert_select ".ibox-title .ibox-tools button.photo-section-camera-button", count: 1
    assert_select ".ibox-title .ibox-tools button.photo-section-upload-button", count: 1
    assert_select ".ibox-title .ibox-tools button.photo-section-info-button", count: 1
    assert_select "a[data-pswp-remove-path='#{photo_notebook_chapter_page_path(@notebook, @chapter, @page, page_attachment)}']", count: 1

    get notepad_entry_path(entry)

    assert_response :success
    assert_no_match "Manage photos", response.body
    assert_select ".detail-photo-gallery-actions-form", count: 1
    assert_select ".ibox-title .ibox-tools button.photo-section-camera-button", count: 1
    assert_select ".ibox-title .ibox-tools button.photo-section-upload-button", count: 1
    assert_select ".ibox-title .ibox-tools button.photo-section-info-button", count: 1
    assert_select "a[data-pswp-remove-path='#{photo_notepad_entry_path(entry, entry_attachment)}']", count: 1
  end

  test "notebook and page views still render when page enhancement tables are unavailable" do
    sign_in!
    notepad_entry = @user.notepad_entries.create!(
      title: "Daily page",
      notes: "Quick note",
      entry_date: Date.current
    )

    VoiceNote.stub(:schema_ready?, false) do
      TodoList.stub(:schema_ready?, false) do
        TodoItem.stub(:schema_ready?, false) do
          Reminder.stub(:schema_ready?, false) do
            get notebook_path(@notebook)
            assert_response :success

            get notebook_chapter_page_path(@notebook, @chapter, @page)
            assert_response :success
            assert_match "To-do list", response.body
            assert_match "To-do list is not ready yet", response.body

            get edit_notebook_chapter_page_path(@notebook, @chapter, @page)
            assert_response :success
            assert_match "To-do list", response.body
            assert_match "To-do list is not ready yet", response.body

            get notepad_entry_path(notepad_entry)
            assert_response :success
            assert_match "To-do list", response.body
            assert_match "To-do list is not ready yet", response.body

            get edit_notepad_entry_path(notepad_entry)
            assert_response :success
            assert_match "To-do list", response.body
            assert_match "To-do list is not ready yet", response.body
          end
        end
      end
    end
  end

  test "page view still renders checklist items when reminders are unavailable in the schema" do
    sign_in!

    todo_list = @page.create_todo_list!(enabled: true, hide_completed: false)
    todo_list.todo_items.create!(content: "Follow up with client", position: 1)

    Reminder.stub(:schema_ready?, false) do
      get notebook_chapter_page_path(@notebook, @chapter, @page)

      assert_response :success
      assert_match "Follow up with client", response.body
      refute_match "Add reminder", response.body
    end
  end

  test "workspace footer exposes the mobile quick action menu" do
    sign_in!

    get dashboard_path

    assert_response :success
    assert_select "[data-controller='footer-action-menu']", count: 1
    assert_select "button[data-action='footer-action-menu#toggle'][aria-controls='mobile-footer-leaf-actions']", count: 1
    assert_select "a.mobile-footer-action-menu__item[href='#{capture_studio_path}']", text: /Quick capture/
    assert_select "a.mobile-footer-action-menu__item[href='#{reminders_path}']", text: /Reminder/
    assert_select "a.mobile-footer-action-menu__item[href='#{tasks_path}']", text: /To-do/
  end

  test "reminders page lists upcoming and historical reminders" do
    sign_in!

    @user.reminders.create!(title: "Later upcoming", fire_at: 2.days.from_now)
    @user.reminders.create!(title: "Sooner upcoming", fire_at: 2.hours.from_now)
    overdue_pending = @user.reminders.create!(title: "Overdue pending", fire_at: 15.minutes.ago)
    @user.reminders.create!(title: "Older history", fire_at: 3.days.ago, status: :triggered, last_triggered_at: 2.days.ago)
    newer_history = @user.reminders.create!(title: "Newer history", fire_at: 2.days.ago, status: :dismissed, last_triggered_at: 1.day.ago)

    get reminders_path

    assert_response :success
    assert_select "h5", text: "Upcoming reminders"
    assert_select "h5", text: "Reminder history"
    assert_match "Sooner upcoming", response.body
    assert_match "Later upcoming", response.body
    assert_match "Overdue pending", response.body
    assert_match "Newer history", response.body
    assert_match "Older history", response.body
    assert_select "input[name='reminder[fire_at_local]']"
    assert_select ".reminders-page__upcoming-content .notebook-list-card--reminder", minimum: 2
    assert_select ".reminders-page__history-content .notebook-list-card--reminder", minimum: 1
    assert overdue_pending.reload.status_expired?
    assert newer_history.reload.status_expired?
    assert_select ".reminders-page__history-content .home-reminder-card__status", text: "Expired", minimum: 1
    assert_select "#reminderDismissConfirmModal", count: 1
    assert_select "button[data-action='reminder-dismiss-confirm#open']", minimum: 1
    assert_operator response.body.index("Sooner upcoming"), :<, response.body.index("Later upcoming")
    assert_operator response.body.index("Overdue pending"), :>, response.body.index("Later upcoming")
    assert_operator response.body.index("Newer history"), :<, response.body.index("Older history")
  end

  test "reminder edit page keeps action buttons in the dedicated action bar" do
    sign_in!

    reminder = @user.reminders.create!(title: "Check status", fire_at: 3.hours.from_now)

    get edit_reminder_path(reminder)

    assert_response :success
    assert_select ".reminder-edit-actions", minimum: 1
    assert_select ".reminder-edit-actions .btn", text: "Save reminder"
    assert_select ".reminder-edit-actions .btn", text: "Delete reminder"
    assert_select ".reminder-edit-actions .btn.btn-sm", minimum: 2
  end

  test "tasks page can prefill the reminder due date" do
    sign_in!

    reminder_date = Date.current

    get tasks_path(task: { due_date: reminder_date.iso8601 })

    assert_response :success
    assert_select "input[name='task[due_date]'][value='#{reminder_date.iso8601}']"
  end

  test "install page shows notification setup step" do
    sign_in!

    get install_path

    assert_response :success
    assert_select "[data-controller='install-prompt']", count: 1
    assert_select "[data-install-prompt-target='notificationSetup']", count: 1
    assert_select "button[data-action='install-prompt#requestNotifications']", text: "Enable notifications"
  end

  private

  def sign_in!
    cookies[:browser_time_zone] = "UTC"

    get browser_sign_in_path

    post browser_sign_in_path, params: {
      authenticity_token: authenticity_token_for(browser_sign_in_path),
      user: { email: @user.email, password: "Password123!" }
    }

    assert_redirected_to dashboard_path
  end

  def authenticity_token_for(action_path)
    document = Nokogiri::HTML.parse(response.body)
    form = document.css("form").find do |node|
      URI.parse(node["action"]).path == action_path
    end

    raise "No form found for #{action_path}" unless form

    form.at_css("input[name='authenticity_token']")["value"]
  end
end
