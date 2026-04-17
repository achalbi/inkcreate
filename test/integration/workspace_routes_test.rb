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

  test "workspace header description starts collapsed behind the info toggle" do
    sign_in!

    get dashboard_path

    assert_response :success

    document = Nokogiri::HTML.parse(response.body)
    toggle = document.at_css(".workspace-header__info-toggle")
    lead = document.at_css(".workspace-header__lead")

    assert toggle.present?, "Expected the shared workspace header to render an info toggle"
    assert lead.present?, "Expected the shared workspace header to render a page lead container"
    assert_equal "false", toggle["aria-expanded"]
    assert_equal "Toggle page description", toggle["aria-label"]
    assert_equal lead["id"], toggle["aria-controls"]
    assert_includes toggle["class"], "collapsed"
    refute_includes lead["class"].to_s.split(/\s+/), "show"
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

  test "workspace topbar shows the google drive sync button when drive is ready" do
    @user.update!(
      google_drive_connected_at: Time.current,
      google_drive_refresh_token: "refresh-token",
      google_drive_folder_id: "drive-folder-123"
    )
    @user.ensure_app_setting!.update!(backup_enabled: true, backup_provider: "google_drive")

    sign_in!
    get dashboard_path

    assert_response :success
    assert_select "form[action='#{sync_settings_backup_path}']"
    assert_select "button", text: /Sync Drive/
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
    start_button = document.at_xpath("//section[contains(@data-controller, 'voice-recorder')]//*[contains(@class, 'ibox-title') or contains(@class, 'notepad-doc__block-header')]//button[@data-action='voice-recorder#start']")
    button = document.at_xpath("//button[@data-bs-toggle='modal' and @data-bs-target='##{modal_id}']")
    modal = document.at_xpath("//*[@id='#{modal_id}']")
    form = modal&.at_xpath(".//form[@method='post']")

    assert start_button.present?, "Expected voice note record button in the section header"
    assert_equal "Record", start_button.text.strip
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
    start_button = document.at_xpath("//section[contains(@data-controller, 'voice-recorder')]//*[contains(@class, 'ibox-title') or contains(@class, 'notepad-doc__block-header')]//button[@data-action='voice-recorder#start']")
    button = document.at_xpath("//button[@data-bs-toggle='modal' and @data-bs-target='##{modal_id}']")
    modal = document.at_xpath("//*[@id='#{modal_id}']")
    form = modal&.at_xpath(".//form[@method='post']")

    assert start_button.present?, "Expected voice note record button in the section header"
    assert_equal "Record", start_button.text.strip
    assert button.present?, "Expected delete trigger button for voice note modal"
    assert modal.present?, "Expected delete confirmation modal to be rendered"
    assert form.present?, "Expected delete confirmation form inside the voice note modal"
    assert_equal notebook_chapter_page_voice_note_path(@notebook, @chapter, @page, voice_note), URI.parse(form["action"]).path
    assert_equal "delete", form.at_xpath(".//input[@name='_method']")&.[]("value")
  end

  test "notepad edit page hides transcript actions for existing voice notes" do
    sign_in!

    entry = @user.notepad_entries.create!(
      title: "Transcript entry",
      notes: "Contains a transcribed voice note.",
      entry_date: Date.current
    )
    voice_note = entry.voice_notes.new(
      duration_seconds: 18,
      recorded_at: Time.current,
      byte_size: 128,
      mime_type: "audio/webm",
      transcript: "Follow up with pricing details tomorrow morning."
    )
    voice_note.audio.attach(
      io: StringIO.new("voice"),
      filename: "note.webm",
      content_type: "audio/webm"
    )
    voice_note.save!

    get edit_notepad_entry_path(entry)

    assert_response :success
    document = Nokogiri::HTML.parse(response.body)
    card = document.at_css("article.voice-note-list-card")

    assert card.present?, "Expected a rendered notepad voice note card"
    assert card.at_xpath(".//a[@download='note.webm']").present?, "Expected the download action to remain available"
    assert card.at_xpath(".//button[@data-bs-target='##{ActionView::RecordIdentifier.dom_id(voice_note, :delete_confirm_modal)}']").present?, "Expected the delete action to remain available"
    assert_nil card["data-controller"], "Voice note card should no longer mount transcript controls"
    assert_nil card.at_xpath(".//*[contains(@class, 'voice-note-transcript')]"), "Transcript UI should not render"
    refute_includes response.body, submit_transcript_notepad_entry_voice_note_path(entry, voice_note)
  end

  test "notepad edit page renders floating quick actions launcher" do
    sign_in!

    entry = @user.notepad_entries.create!(
      title: "Launcher entry",
      notes: "Launcher notes",
      entry_date: Date.current
    )

    get edit_notepad_entry_path(entry)

    assert_response :success

    document = Nokogiri::HTML.parse(response.body)
    launcher = document.at_css(".notepad-quick-actions[data-controller='notepad-quick-actions']")
    toggle = launcher&.at_css(".notepad-quick-actions__toggle")
    items = launcher&.css(".notepad-quick-actions__item i")&.map { |node| node["class"].to_s[/ti-[^ ]+/] }

    assert launcher.present?, "Expected the notepad quick actions launcher"
    assert toggle.present?, "Expected the quick actions + toggle button"
    assert_equal "false", toggle["aria-expanded"]
    assert_equal %w[ti-camera ti-photo-plus ti-microphone ti-list-check ti-scan], items
  end

  test "page edit page renders floating quick actions launcher" do
    sign_in!

    get edit_notebook_chapter_page_path(@notebook, @chapter, @page)

    assert_response :success

    document = Nokogiri::HTML.parse(response.body)
    launcher = document.at_css(".notepad-quick-actions[data-controller='notepad-quick-actions']")
    toggle = launcher&.at_css(".notepad-quick-actions__toggle")
    items = launcher&.css(".notepad-quick-actions__item i")&.map { |node| node["class"].to_s[/ti-[^ ]+/] }

    assert launcher.present?, "Expected the notebook page edit screen to render the quick actions launcher"
    assert toggle.present?, "Expected the quick actions + toggle button"
    assert_equal "false", toggle["aria-expanded"]
    assert_equal %w[ti-camera ti-photo-plus ti-microphone ti-list-check ti-scan], items
  end

  test "notepad edit page renders floating section dock" do
    sign_in!

    entry = @user.notepad_entries.create!(
      title: "Dock entry",
      notes: "Dock notes",
      entry_date: Date.current
    )

    get edit_notepad_entry_path(entry)

    assert_response :success

    document = Nokogiri::HTML.parse(response.body)
    dock = document.at_css("nav.detail-section-shortcuts[data-controller='section-shortcuts']")
    links = dock&.css(".detail-section-shortcut")&.map { |node| node["href"] }

    assert dock.present?, "Expected the notepad edit page to render the floating section dock"
    assert_includes links, "##{ActionView::RecordIdentifier.dom_id(entry, :details_section)}"
    assert_includes links, "##{ActionView::RecordIdentifier.dom_id(entry, :photos_section)}"
    assert_includes links, "##{ActionView::RecordIdentifier.dom_id(entry, :voice_notes_section)}"
    assert_includes links, "##{ActionView::RecordIdentifier.dom_id(entry, :todo_list_section)}"
    assert_includes links, "##{ActionView::RecordIdentifier.dom_id(entry, :scanned_documents_section)}"
    assert_includes links, "##{ActionView::RecordIdentifier.dom_id(entry, :move_to_notebook_section)}"
  end

  test "page edit page hides transcript actions for existing voice notes" do
    sign_in!

    voice_note = @page.voice_notes.new(
      duration_seconds: 24,
      recorded_at: Time.current,
      byte_size: 128,
      mime_type: "audio/webm",
      transcript: "Key decision captured and action owner assigned."
    )
    voice_note.audio.attach(
      io: StringIO.new("voice"),
      filename: "page-note.webm",
      content_type: "audio/webm"
    )
    voice_note.save!

    get edit_notebook_chapter_page_path(@notebook, @chapter, @page)

    assert_response :success
    document = Nokogiri::HTML.parse(response.body)
    card = document.at_css("article.voice-note-list-card")

    assert card.present?, "Expected a rendered page voice note card"
    assert card.at_xpath(".//a[@download='page-note.webm']").present?, "Expected the download action to remain available"
    assert card.at_xpath(".//button[@data-bs-target='##{ActionView::RecordIdentifier.dom_id(voice_note, :delete_confirm_modal)}']").present?, "Expected the delete action to remain available"
    assert_nil card["data-controller"], "Voice note card should no longer mount transcript controls"
    assert_nil card.at_xpath(".//*[contains(@class, 'voice-note-transcript')]"), "Transcript UI should not render"
    refute_includes response.body, submit_transcript_notebook_chapter_page_voice_note_path(@notebook, @chapter, @page, voice_note)
  end

  test "notepad show page keeps scanned document cards focused on pdf actions" do
    sign_in!

    entry = @user.notepad_entries.create!(
      title: "Scanned document page",
      notes: "Contains a saved scan.",
      entry_date: Date.current
    )
    scanned_document = entry.scanned_documents.new(
      user: @user,
      title: "Receipt",
      extracted_text: "Total due 42.00",
      ocr_engine: "tesseract",
      ocr_language: "eng",
      ocr_confidence: 88
    )
    scanned_document.enhanced_image.attach(
      io: StringIO.new("image"),
      filename: "receipt.jpg",
      content_type: "image/jpeg"
    )
    scanned_document.document_pdf.attach(
      io: StringIO.new("%PDF-1.4 receipt"),
      filename: "receipt.pdf",
      content_type: "application/pdf"
    )
    scanned_document.save!

    get notepad_entry_path(entry)

    assert_response :success
    document = Nokogiri::HTML.parse(response.body)
    card = document.at_css("##{ActionView::RecordIdentifier.dom_id(scanned_document)}")

    assert card.present?, "Expected a rendered scanned document card"
    assert_equal "PDF ready · #{scanned_document.created_at.strftime("%-d %b")}", card.at_css(".sdoc-engine-label")&.text&.strip
    assert_nil card.at_css(".sdoc-excerpt"), "Helper copy should not render"
    assert_nil card.at_xpath(".//form[contains(@action, '#{extract_text_notepad_entry_scanned_document_path(entry, scanned_document)}')]"), "OCR action should not render"
    assert_nil card.at_xpath(".//*[@data-action='click->document-capture#copyText']"), "Copy extracted text action should not render"
    assert_nil card.at_xpath(".//*[@data-action='click->document-capture#viewFull']"), "View extracted text action should not render"
    assert_nil card.at_css(".sdoc-conf-badge"), "OCR confidence badge should not render"
    refute_includes response.body, "Total due 42.00"
  end

  test "notepad show page exposes the pdf export link" do
    sign_in!

    entry = @user.notepad_entries.create!(
      title: "Exportable entry",
      notes: "Ready for export.",
      entry_date: Date.current
    )

    get notepad_entry_path(entry)

    assert_response :success
    assert_select "a.notepad-doc__meta-action[href='#{pdf_notepad_entry_path(entry, autoprint: 1)}'][target='_blank']", text: /PDF/
    refute_includes response.body, "Markdown"
    refute_includes response.body, "Plain text / ASCII doc"
  end

  test "notepad pdf export includes all visible content sections" do
    sign_in!

    entry = @user.notepad_entries.create!(
      title: "Full export entry",
      notes: "<p>Export the <strong>rich notes</strong>.</p>",
      entry_date: Date.current
    )
    entry.photos.attach(
      io: StringIO.new("photo-bytes"),
      filename: "desk.jpg",
      content_type: "image/jpeg"
    )

    voice_note = entry.voice_notes.new(
      duration_seconds: 95,
      recorded_at: Time.current.change(sec: 0),
      byte_size: 1024,
      mime_type: "audio/webm",
      transcript: "Voice memo summary."
    )
    voice_note.audio.attach(
      io: StringIO.new("voice"),
      filename: "memo.webm",
      content_type: "audio/webm"
    )
    voice_note.save!

    todo_list = entry.create_todo_list!(enabled: true, hide_completed: false)
    todo_list.todo_items.create!(content: "Capture follow-up actions", completed: true)
    todo_list.todo_items.create!(content: "Share the PDF export", completed: false)

    scanned_document = entry.scanned_documents.new(
      user: @user,
      title: "Meeting scan"
    )
    scanned_document.enhanced_image.attach(
      io: StringIO.new("image"),
      filename: "meeting.jpg",
      content_type: "image/jpeg"
    )
    scanned_document.document_pdf.attach(
      io: StringIO.new("%PDF-1.4 export"),
      filename: "meeting.pdf",
      content_type: "application/pdf"
    )
    scanned_document.save!

    get pdf_notepad_entry_path(entry)

    assert_response :success
    assert_select "html[data-export-format='pdf']", count: 1
    assert_select "body.workspace-body--pdf-export", count: 1
    assert_select ".notepad-doc__title", text: "Full export entry"
    assert_select ".notepad-doc__block--text strong", text: "rich notes"
    assert_select ".notepad-doc__block--media .notepad-doc__photo-strip .notepad-doc__photo-item", count: 1
    assert_select ".notepad-doc__block--voice .voice-note-list-card--export", count: 1
    assert_select ".notepad-doc__block--voice", text: /Voice memo summary/
    assert_select ".notepad-doc__block--todos .todo-list-item", count: 2
    assert_select ".notepad-doc__block--scans .sdoc-card", count: 1
    assert_select ".notepad-doc__block--scans", text: /Meeting scan/
  end

  test "page show page keeps scanned document cards focused on pdf actions" do
    sign_in!

    scanned_document = @page.scanned_documents.new(
      user: @user,
      title: "Agenda",
      extracted_text: "Action items and owners.",
      ocr_engine: "tesseract",
      ocr_language: "eng",
      ocr_confidence: 91
    )
    scanned_document.enhanced_image.attach(
      io: StringIO.new("image"),
      filename: "agenda.jpg",
      content_type: "image/jpeg"
    )
    scanned_document.document_pdf.attach(
      io: StringIO.new("%PDF-1.4 agenda"),
      filename: "agenda.pdf",
      content_type: "application/pdf"
    )
    scanned_document.save!

    get notebook_chapter_page_path(@notebook, @chapter, @page)

    assert_response :success
    document = Nokogiri::HTML.parse(response.body)
    card = document.at_css("##{ActionView::RecordIdentifier.dom_id(scanned_document)}")

    assert card.present?, "Expected a rendered scanned document card"
    assert_equal "PDF ready · #{scanned_document.created_at.strftime("%-d %b")}", card.at_css(".sdoc-engine-label")&.text&.strip
    assert_nil card.at_css(".sdoc-excerpt"), "Helper copy should not render"
    assert_nil card.at_xpath(".//form[contains(@action, '#{extract_text_notebook_chapter_page_scanned_document_path(@notebook, @chapter, @page, scanned_document)}')]"), "OCR action should not render"
    assert_nil card.at_xpath(".//*[@data-action='click->document-capture#copyText']"), "Copy extracted text action should not render"
    assert_nil card.at_xpath(".//*[@data-action='click->document-capture#viewFull']"), "View extracted text action should not render"
    assert_nil card.at_css(".sdoc-conf-badge"), "OCR confidence badge should not render"
    refute_includes response.body, "Action items and owners."
  end

  test "page edit page renders the live to-do list section for persisted pages" do
    sign_in!

    todo_list = @page.create_todo_list!(enabled: true, hide_completed: false)
    todo_list.todo_items.create!(content: "Pack charger", position: 1, completed: false)
    todo_list.todo_items.create!(content: "Review notes", position: 2, completed: true)

    get edit_notebook_chapter_page_path(@notebook, @chapter, @page)

    assert_response :success
    document = Nokogiri::HTML.parse(response.body)
    edit_form_id = ActionView::RecordIdentifier.dom_id(@page, :edit_form)
    edit_form = document.at_css("form##{edit_form_id}")
    todo_section = document.at_css("##{ActionView::RecordIdentifier.dom_id(@page, :todo_list_section)}")
    save_button = document.at_css(".notepad-doc-edit__footer .page-details-save-button[form='#{edit_form_id}']")

    assert_select "form[action='#{notebook_chapter_page_todo_items_path(@notebook, @chapter, @page)}'] textarea[name='todo_item[content]']", count: 1
    assert_select "form[action='#{notebook_chapter_page_todo_items_path(@notebook, @chapter, @page)}'] .todo-list-composer__badge .ti-checkbox", count: 1
    assert_select "form[action='#{notebook_chapter_page_todo_items_path(@notebook, @chapter, @page)}'] .todo-list-composer__submit .ti-plus", count: 1
    assert_select ".todo-list-progress__summary", text: /1 of 2 completed/
    assert_select ".todo-list-item__input[title='Pack charger']", count: 1
    assert_select ".todo-list-item__input[title='Review notes']", count: 1
    assert edit_form.present?, "Expected the page update form to render on the edit page"
    assert todo_section.present?, "Expected the live to-do section to render"
    assert_nil edit_form.at_css("##{ActionView::RecordIdentifier.dom_id(@page, :todo_list_section)}"),
      "Expected the live to-do section to stay outside the page update form"
    assert save_button.present?, "Expected the save button to target the page update form explicitly"
    delete_form = document.at_css(".notepad-doc-edit__footer form.button_to[action='#{notebook_chapter_page_path(@notebook, @chapter, @page)}']")
    assert delete_form.present?, "Expected the persisted page edit footer to render a delete form"
    assert_equal "return confirm('Delete this page?');", delete_form["onsubmit"]
    assert_no_match "Enable the checklist and queue items before saving this page.", response.body
    assert_no_match "Saved items on this page", response.body
    assert_select "nav.detail-section-shortcuts[data-controller='section-shortcuts']", count: 1
    assert_select "nav.detail-section-shortcuts a[href='##{ActionView::RecordIdentifier.dom_id(@page, :details_section)}']", count: 1
    assert_select "nav.detail-section-shortcuts a[href='##{ActionView::RecordIdentifier.dom_id(@page, :notes_section)}']", count: 1
    assert_select "nav.detail-section-shortcuts a[href='##{ActionView::RecordIdentifier.dom_id(@page, :photos_section)}']", count: 1
    assert_select ".notepad-doc__meta a.notepad-doc__meta-action[href='#{notebook_chapter_page_path(@notebook, @chapter, @page)}']", text: /View/
    assert_select ".notepad-doc__meta form.button_to[action='#{quick_create_notebook_chapter_pages_path(@notebook, @chapter)}'] button.notepad-doc__meta-action", text: /New page/
  end

  test "new page form shows the to-do composer without an enable toggle" do
    sign_in!

    get new_notebook_chapter_page_path(@notebook, @chapter)

    assert_response :success
    document = Nokogiri::HTML.parse(response.body)
    launcher = document.at_css(".notepad-quick-actions[data-controller='notepad-quick-actions']")
    items = launcher&.css(".notepad-quick-actions__item i")&.map { |node| node["class"].to_s[/ti-[^ ]+/] }

    assert_select ".notepad-doc-edit__canvas", count: 1
    assert_select ".notepad-doc__block--voice", count: 1
    assert_select ".notepad-doc__block--scans", count: 1
    assert_select ".notepad-doc__block--todos", count: 1
    assert_select "textarea[data-todo-list-target='draftInput']", count: 1
    assert_select ".todo-list-composer__badge .ti-checkbox", count: 1
    assert_select ".todo-list-composer__submit .ti-plus", count: 1
    assert_select "input[name='page[todo_list_enabled]'][value='false']", count: 1
    assert_no_match "Enable list", response.body
    assert_no_match "Enable to-do list", response.body
    assert_no_match "Enable the checklist and queue items before saving this page.", response.body
    assert_no_match "Saved with this form", response.body
    assert_match "Add checklist items before saving.", response.body
    assert launcher.present?, "Expected the notebook new page screen to render the quick actions launcher"
    assert_equal %w[ti-camera ti-photo-plus ti-microphone ti-list-check ti-scan], items
    assert_select "nav.detail-section-shortcuts[data-controller='section-shortcuts']", count: 1
    assert_select "nav.detail-section-shortcuts a[href='##{ActionView::RecordIdentifier.dom_id(Page.new, :details_section)}']", count: 1
    assert_select "nav.detail-section-shortcuts a[href='##{ActionView::RecordIdentifier.dom_id(Page.new, :notes_section)}']", count: 1
    assert_select "nav.detail-section-shortcuts a[href='##{ActionView::RecordIdentifier.dom_id(Page.new, :photos_section)}']", count: 1
    assert_select ".notepad-doc__meta a.notepad-doc__meta-action[href='#{notebook_chapter_path(@notebook, @chapter)}']", text: /Chapter/
  end

  test "chapter show page exposes the new page action without inline page edit controls" do
    sign_in!

    get notebook_chapter_path(@notebook, @chapter)

    assert_response :success
    assert_select "a.notebook-detail-section__add[href='#{new_notebook_chapter_page_path(@notebook, @chapter)}']", text: /New page/
    assert_select ".notebook-list-card__inline-action", count: 0
    assert_select "form.button_to[action='#{quick_create_notebook_chapter_pages_path(@notebook, @chapter)}'] button.workspace-fab", count: 1
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
    document = Nokogiri::HTML.parse(response.body)
    edit_form_id = ActionView::RecordIdentifier.dom_id(entry, :edit_form)
    edit_form = document.at_css("form##{edit_form_id}")
    todo_section = document.at_css("##{ActionView::RecordIdentifier.dom_id(entry, :todo_list_section)}")
    save_button = document.at_css(".notepad-doc-edit__footer .page-details-save-button[form='#{edit_form_id}']")

    assert_select "form[action='#{notepad_entry_todo_items_path(entry)}'] textarea[name='todo_item[content]']", count: 1
    assert_select "form[action='#{notepad_entry_todo_items_path(entry)}'] .todo-list-composer__badge .ti-checkbox", count: 1
    assert_select "form[action='#{notepad_entry_todo_items_path(entry)}'] .todo-list-composer__submit .ti-plus", count: 1
    assert_select ".todo-list-progress__summary", text: /1 of 2 completed/
    assert_select ".todo-list-item__input[title='Pack charger']", count: 1
    assert_select ".todo-list-item__input[title='Review notes']", count: 1
    assert edit_form.present?, "Expected the page update form to render on the edit page"
    assert todo_section.present?, "Expected the live to-do section to render"
    assert_nil edit_form.at_css("##{ActionView::RecordIdentifier.dom_id(entry, :todo_list_section)}"),
      "Expected the live to-do section to stay outside the page update form"
    assert save_button.present?, "Expected the save button to target the page update form explicitly"
    assert_no_match "Enable the checklist and queue items before saving this page.", response.body
    assert_no_match "Saved items on this page", response.body
    assert_operator response.body.index("To-do list"), :<, response.body.index("Move to notebook")
  end

  test "notepad edit page renders the upgraded notes editor shell" do
    sign_in!

    entry = @user.notepad_entries.create!(
      title: "Notes shell page",
      notes: "Editor styling should stay contained.",
      entry_date: Date.current
    )

    get edit_notepad_entry_path(entry)

    assert_response :success
    assert_select ".notepad-doc-edit__notes .notepad-doc-edit__notes-shell", count: 1
    assert_select ".notepad-doc-edit__notes .notepad-doc-edit__notes-shell trix-editor.notepad-entry-notes-field", count: 1
  end

  test "new notepad form shows the to-do composer without an enable toggle" do
    sign_in!

    get new_notepad_entry_path

    assert_response :success
    assert_select ".notepad-doc-edit__canvas", count: 1
    assert_select ".notepad-doc__block--voice", count: 1
    assert_select ".notepad-doc__block--scans", count: 1
    assert_select ".notepad-doc__block--todos", count: 1
    assert_select "textarea[data-todo-list-target='draftInput']", count: 1
    assert_select ".todo-list-composer__badge .ti-checkbox", count: 1
    assert_select ".todo-list-composer__submit", count: 1
    assert_select ".todo-list-composer__submit .ti-plus", count: 1
    assert_select "input[name='notepad_entry[todo_list_enabled]'][value='false']", count: 1
    assert_no_match "Enable list", response.body
    assert_no_match "Enable to-do list", response.body
    assert_no_match "Enable the checklist and queue items before saving this page.", response.body
    assert_no_match "Saved with this form", response.body
    assert_match "Add checklist items before saving.", response.body
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
    assert_select ".ibox-title .ibox-tools button.photo-section-camera-button", count: 0
    assert_select ".ibox-title .ibox-tools button.photo-section-upload-button", count: 0
    assert_select ".ibox-title .ibox-tools button.photo-section-info-button", count: 1
    assert_select ".ibox-content > .ibox-content__inner button.photo-section-upload-button", count: 1, text: /Upload/
    assert_select ".ibox-content > .ibox-content__inner button.photo-section-info-button", count: 0
    assert_select ".ibox-content > .ibox-content__inner button.photo-section-camera-button", count: 1, text: /Capture/
    assert_select "a[data-pswp-remove-path='#{photo_notebook_chapter_page_path(@notebook, @chapter, @page, page_attachment)}']", count: 1
    assert_select "nav.detail-section-shortcuts[data-controller='section-shortcuts']", count: 1
    assert_select "nav.detail-section-shortcuts a[href='##{ActionView::RecordIdentifier.dom_id(@page, :overview_section)}']", count: 1
    assert_select "nav.detail-section-shortcuts a.is-active[aria-current='location'][href='##{ActionView::RecordIdentifier.dom_id(@page, :overview_section)}']", count: 1
    assert_select "nav.detail-section-shortcuts a[href='##{ActionView::RecordIdentifier.dom_id(@page, :photos_section)}']", count: 1
    assert_select "nav.detail-section-shortcuts a[href='##{ActionView::RecordIdentifier.dom_id(@page, :voice_notes_section)}']", count: 1
    assert_select "nav.detail-section-shortcuts a[href='##{ActionView::RecordIdentifier.dom_id(@page, :todo_list_section)}']", count: 1
    assert_select "nav.detail-section-shortcuts a[href='##{ActionView::RecordIdentifier.dom_id(@page, :scanned_documents_section)}']", count: 1
    assert_select "nav.detail-section-shortcuts a[href='##{ActionView::RecordIdentifier.dom_id(@page, :move_to_notebook_section)}']", count: 1

    get notepad_entry_path(entry)

    assert_response :success
    assert_no_match "Manage photos", response.body
    assert_no_match "Web scan mode", response.body
    assert_no_match "Native scanner available", response.body
    assert_select ".detail-photo-gallery-actions-form", count: 1
    assert_select ".ibox-title .ibox-tools button.photo-section-camera-button", count: 0
    assert_select ".ibox-title .ibox-tools button.photo-section-upload-button", count: 0
    assert_select ".ibox-title .ibox-tools button.photo-section-info-button", count: 1
    assert_select ".ibox-content > .ibox-content__inner button.photo-section-upload-button", count: 1, text: /Upload/
    assert_select ".ibox-content > .ibox-content__inner button.photo-section-info-button", count: 0
    assert_select ".ibox-content > .ibox-content__inner button.photo-section-camera-button", count: 1, text: /Capture/
    assert_select ".ibox-title .ibox-tools .notebook-overview-delete-button", count: 0
    assert_select "nav.detail-section-shortcuts[data-controller='section-shortcuts']", count: 1
    assert_select "nav.detail-section-shortcuts a[href='##{ActionView::RecordIdentifier.dom_id(entry, :overview_section)}']", count: 1
    assert_select "nav.detail-section-shortcuts a.is-active[aria-current='location'][href='##{ActionView::RecordIdentifier.dom_id(entry, :overview_section)}']", count: 1
    assert_select "nav.detail-section-shortcuts a[href='##{ActionView::RecordIdentifier.dom_id(entry, :photos_section)}']", count: 1
    assert_select "nav.detail-section-shortcuts a[href='##{ActionView::RecordIdentifier.dom_id(entry, :voice_notes_section)}']", count: 1
    assert_select "nav.detail-section-shortcuts a[href='##{ActionView::RecordIdentifier.dom_id(entry, :todo_list_section)}']", count: 1
    assert_select "nav.detail-section-shortcuts a[href='##{ActionView::RecordIdentifier.dom_id(entry, :scanned_documents_section)}']", count: 1
    assert_select "nav.detail-section-shortcuts a[href='##{ActionView::RecordIdentifier.dom_id(entry, :move_to_notebook_section)}']", count: 1
    assert_select "a[data-pswp-remove-path='#{photo_notepad_entry_path(entry, entry_attachment)}']", count: 1
  end

  test "page show page renders transfer controls" do
    sign_in!

    destination_notebook = @user.notebooks.create!(
      title: "Archive notebook",
      status: :active
    )
    destination_chapter = destination_notebook.chapters.create!(
      title: "Completed",
      description: "Target chapter"
    )

    get notebook_chapter_page_path(@notebook, @chapter, @page)

    assert_response :success
    move_form_id = ActionView::RecordIdentifier.dom_id(@page, :move_form)
    move_modal_id = ActionView::RecordIdentifier.dom_id(@page, :move_destination_modal)

    assert_select ".page-move-shell", count: 1
    assert_select "form##{move_form_id}[action='#{notebook_chapter_page_path(@notebook, @chapter, @page)}']", count: 1
    assert_select "form##{move_form_id} input[name='_method'][value='patch']", count: 1
    assert_select "input[name='move_to_chapter_id'][form='#{move_form_id}']", count: 1
    assert_select "button[name='intent'][value='move_to_notebook'][form='#{move_form_id}']", count: 0
    assert_select "button[data-bs-target='##{ActionView::RecordIdentifier.dom_id(@page, :move_to_notepad_confirm_modal)}']", text: /Move to notepad/
    assert_select "##{move_modal_id} button[name='intent'][value='move_to_notebook'][form='#{move_form_id}'][data-action='click->move-destination#commitSelection']", text: /Move to notebook chapter/
    assert_select "##{ActionView::RecordIdentifier.dom_id(@page, :move_to_notepad_confirm_modal)} button[name='intent'][value='move_to_notepad'][form='#{move_form_id}']", text: /Move to notepad/
    assert_select "##{move_modal_id} [data-move-destination-target='notebookMenu']", count: 1
    assert_select "##{move_modal_id} [data-move-destination-target='notebookMenu'] button.dropdown-item[data-notebook-id='#{destination_notebook.id}']", text: /#{Regexp.escape(destination_notebook.title)}/
    assert_select "##{move_modal_id} [data-move-destination-target='chapterMenu']", count: 1
    assert_select "##{move_modal_id} [data-move-destination-target='chapterMenu'] button.dropdown-item.disabled", text: /Choose a notebook first/
    assert_select "##{move_modal_id} [data-bs-toggle='dropdown']", count: 2
    assert_select "##{move_modal_id} select", count: 0
  end

  test "page show page exposes edit and new page actions in the document header" do
    sign_in!

    get notebook_chapter_page_path(@notebook, @chapter, @page)

    assert_response :success
    document = Nokogiri::HTML.parse(response.body)
    launcher = document.at_css(".notepad-quick-actions[data-controller='notepad-quick-actions']")
    toggle = launcher&.at_css(".notepad-quick-actions__toggle")
    items = launcher&.css(".notepad-quick-actions__item i")&.map { |node| node["class"].to_s[/ti-[^ ]+/] }
    delete_form = document.at_css(".notepad-doc__meta form.button_to[action='#{notebook_chapter_page_path(@notebook, @chapter, @page)}']")

    assert_select ".notepad-doc__header##{ActionView::RecordIdentifier.dom_id(@page, :overview_section)}", count: 1
    assert_select "a.notepad-doc__meta-action[href='#{edit_notebook_chapter_page_path(@notebook, @chapter, @page)}']", text: /Edit/
    assert_select ".notepad-doc__meta form.button_to[action='#{quick_create_notebook_chapter_pages_path(@notebook, @chapter)}'] button.notepad-doc__meta-action", text: /New page/
    assert delete_form.present?, "Expected the notebook page header to render a delete form"
    assert_equal "return confirm('Delete this page?');", delete_form["onsubmit"]
    assert_equal "Delete", delete_form.at_css("button.notepad-doc__meta-action")&.text&.strip
    assert_select ".notepad-doc__title", text: @page.display_title
    assert launcher.present?, "Expected the notebook page show screen to render the quick actions launcher"
    assert toggle.present?, "Expected the quick actions + toggle button"
    assert_equal "false", toggle["aria-expanded"]
    assert_equal %w[ti-camera ti-photo-plus ti-microphone ti-list-check ti-scan], items
  end

  test "notepad show page renders a quick edit modal for title and notes" do
    sign_in!

    entry = @user.notepad_entries.create!(
      title: "Quick edit page",
      notes: "Original notes",
      entry_date: Date.current
    )

    get notepad_entry_path(entry)

    assert_response :success
    modal_id = ActionView::RecordIdentifier.dom_id(entry, :quick_edit_modal)
    document = Nokogiri::HTML.parse(response.body)
    button = document.at_xpath("//button[@data-bs-toggle='modal' and @data-bs-target='##{modal_id}']")
    modal = document.at_xpath("//*[@id='#{modal_id}']")
    form = modal&.at_xpath(".//form[@method='post']")
    title_input = modal&.at_xpath(".//input[@name='notepad_entry[title]']")
    notes_input = modal&.at_xpath(".//input[@name='notepad_entry[notes]']")
    trix_editor = modal&.at_xpath(".//trix-editor[@input='#{notes_input&.[]('id')}']")

    assert button.present?, "Expected quick edit trigger button on the notepad show page"
    assert modal.present?, "Expected quick edit modal to be rendered on the notepad show page"
    assert form.present?, "Expected quick edit modal form to be rendered"
    assert_equal notepad_entry_path(entry), URI.parse(form["action"]).path
    assert_equal "patch", form.at_xpath(".//input[@name='_method']")&.[]("value")
    assert form.at_xpath(".//input[@name='quick_edit_modal'][@value='1']").present?, "Expected quick edit modal marker"
    assert title_input.present?, "Expected title field in quick edit modal"
    assert notes_input.present?, "Expected notes field in quick edit modal"
    assert trix_editor.present?, "Expected rich-text editor in quick edit modal"
    assert_nil modal.at_xpath(".//input[@name='notepad_entry[entry_date]']"), "Quick edit modal should not expose entry date"
  end

  test "notepad show page renders move to notebook controls" do
    sign_in!

    destination_notebook = @user.notebooks.create!(
      title: "Project notebook",
      status: :active
    )
    destination_chapter = destination_notebook.chapters.create!(
      title: "Planning",
      description: "Target chapter"
    )
    entry = @user.notepad_entries.create!(
      title: "Moveable page",
      notes: "Move this from the show page.",
      entry_date: Date.current
    )

    get notepad_entry_path(entry)

    assert_response :success
    move_form_id = ActionView::RecordIdentifier.dom_id(entry, :move_form)
    move_modal_id = ActionView::RecordIdentifier.dom_id(entry, :move_destination_modal)

    assert_select ".notepad-entry-move-shell", count: 1
    assert_select "form##{move_form_id}[action='#{notepad_entry_path(entry)}']", count: 1
    assert_select "form##{move_form_id} input[name='_method'][value='patch']", count: 1
    assert_select "form##{move_form_id} input[name='notepad_entry[title]'][value='#{entry.title}']", count: 1
    assert_select "form##{move_form_id} input[name='notepad_entry[entry_date]'][value='#{entry.entry_date}']", count: 1
    assert_select "input[name='move_to_chapter_id'][form='#{move_form_id}']", count: 1
    assert_select "button[name='intent'][value='move_to_notebook'][form='#{move_form_id}']", count: 0
    assert_select "##{move_modal_id} button[name='intent'][value='move_to_notebook'][form='#{move_form_id}'][data-action='click->move-destination#commitSelection']", text: /Move to notebook chapter/
    assert_select "##{move_modal_id} [data-move-destination-target='notebookMenu']", count: 1
    assert_select "##{move_modal_id} [data-move-destination-target='notebookMenu'] button.dropdown-item[data-notebook-id='#{destination_notebook.id}']", text: /#{Regexp.escape(destination_notebook.title)}/
    assert_select "##{move_modal_id} [data-move-destination-target='chapterMenu']", count: 1
    assert_select "##{move_modal_id} [data-move-destination-target='chapterMenu'] button.dropdown-item.disabled", text: /Choose a notebook first/
    assert_select "##{move_modal_id} [data-bs-toggle='dropdown']", count: 2
    assert_select "##{move_modal_id} select", count: 0
  end

  test "notepad quick edit updates title and notes without changing other content" do
    sign_in!

    entry = @user.notepad_entries.create!(
      title: "Original title",
      notes: "Original notes",
      entry_date: Date.current
    )
    todo_list = entry.create_todo_list!(enabled: true, hide_completed: false)
    todo_list.todo_items.create!(content: "Follow up", position: 1)

    get notepad_entry_path(entry)

    patch notepad_entry_path(entry), params: {
      authenticity_token: authenticity_token_for(notepad_entry_path(entry)),
      quick_edit_modal: "1",
      notepad_entry: {
        title: "Updated title",
        notes: "Updated notes"
      }
    }

    assert_redirected_to notepad_entry_path(entry)

    entry.reload
    assert_equal "Updated title", entry.title
    assert_equal "Updated notes", entry.plain_notes
    assert_equal Date.current, entry.entry_date
    assert entry.todo_list.enabled?
    assert_equal ["Follow up"], entry.todo_list.todo_items.order(:position).pluck(:content)
  end

  test "notepad quick edit keeps the modal open on validation errors" do
    sign_in!

    entry = @user.notepad_entries.create!(
      title: "Original title",
      notes: "Original notes",
      entry_date: Date.current
    )

    get notepad_entry_path(entry)

    patch notepad_entry_path(entry), params: {
      authenticity_token: authenticity_token_for(notepad_entry_path(entry)),
      quick_edit_modal: "1",
      notepad_entry: {
        title: "",
        notes: ""
      }
    }

    assert_response :unprocessable_entity
    assert_select ".notepad-entry-quick-edit-modal.show", count: 1
    assert_match "Please fix the following:", response.body
    assert_match "Add notes, a photo, a scanned document, a voice note, or a to-do item.", response.body
  end

  test "notepad edit page keeps delete control in the page details action bar" do
    sign_in!

    entry = @user.notepad_entries.create!(
      title: "Editable page",
      notes: "Needs save and delete actions.",
      entry_date: Date.current
    )

    get edit_notepad_entry_path(entry)

    assert_response :success
    assert_select ".notepad-doc-edit__footer .page-details-save-button", count: 1
    assert_select ".notepad-doc-edit__footer a.notebook-overview-delete-button[href='#{notepad_entry_path(entry)}'][data-turbo-method='delete']", count: 1
    assert_select ".workspace-form-actions .notebook-overview-delete-button", count: 0
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
    todo_list = @page.create_todo_list!(enabled: true, hide_completed: false)
    linked_item = todo_list.todo_items.create!(content: "Review agenda", position: 1)
    linked_reminder = @user.reminders.create!(title: "Page follow-up", fire_at: 1.day.from_now, target: linked_item)
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
    assert_select "button[data-action='reminder-dismiss-confirm#open']", count: 0
    assert_select "#reminderSnoozeModal", count: 1
    assert_select "button[data-action='reminder-snooze#open']", minimum: 1
    assert_select ".reminders-page__compact-list button[data-action='reminder-snooze#open'][aria-label='Snooze reminder']", minimum: 1
    assert_select "a.home-reminder-card__title-link[href='#{reminder_path(linked_reminder)}']", text: "Page follow-up"
    assert_select "a[aria-label='Open source for Page follow-up'][href='#{notebook_chapter_page_path(@notebook, @chapter, @page)}']", count: 1
    assert_select "#reminderSnoozeForm button[name='minutes']", count: 6
    assert_select "#reminderSnoozeForm button[name='minutes'][value='15']", text: "15 min"
    assert_select "#reminderSnoozeForm button[name='minutes'][value='60']", text: "1 hr"
    assert_operator response.body.index("Sooner upcoming"), :<, response.body.index("Later upcoming")
    assert_operator response.body.index("Overdue pending"), :>, response.body.index("Later upcoming")
    assert_operator response.body.index("Newer history"), :<, response.body.index("Older history")
  end

  test "reminder show page keeps edit and delete controls in the title bar" do
    sign_in!

    todo_list = @page.create_todo_list!(enabled: true, hide_completed: false)
    todo_item = todo_list.todo_items.create!(content: "Check status source", position: 1)
    reminder = @user.reminders.create!(title: "Check status", fire_at: 3.hours.from_now, target: todo_item)

    get reminder_path(reminder)

    assert_response :success
    assert_select ".workspace-header a.text-uppercase.text-secondary.fw-semibold[href='#{reminders_path}']", text: "Reminder"
    assert_select ".ibox-title .ibox-tools a.btn[href='#{edit_reminder_path(reminder)}']", text: "Edit"
    assert_select ".ibox-title .ibox-tools a.btn[href='#{notebook_chapter_page_path(@notebook, @chapter, @page)}']", text: "Go to source"
    assert_select ".ibox-title .ibox-tools button[data-action='reminder-snooze#open']", text: "Snooze"
    assert_operator response.body.index(">Snooze<"), :<, response.body.index(">Edit<")
    assert_select ".ibox-title .ibox-tools form[action='#{reminder_path(reminder)}']", count: 0
    assert_select ".ibox-content .reminder-edit-actions button[data-bs-target='#reminderDeleteConfirmModal']", text: "Delete"
    assert_select "#reminderDeleteConfirmModal form[action='#{reminder_path(reminder)}'] .btn", text: "Delete"
  end

  test "reminder edit page keeps only save and cancel actions in the dedicated action bar" do
    sign_in!

    reminder = @user.reminders.create!(title: "Check status", fire_at: 3.hours.from_now)

    get edit_reminder_path(reminder)

    assert_response :success
    assert_select ".reminder-edit-actions", minimum: 1
    assert_select ".reminder-edit-actions .btn", text: "Save reminder"
    assert_select ".reminder-edit-actions a.btn[href='#{reminder_path(reminder)}']", text: "Cancel"
    assert_select ".reminder-edit-actions .btn", text: "Delete reminder", count: 0
    assert_select ".reminder-edit-actions .btn", text: "Open source", count: 0
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
    assert_select "button.ibox-toggle-button[data-action='install-prompt#toggleCollapse'][aria-expanded='true']"
    assert_select "button[data-action='install-prompt#requestNotifications']", text: "Enable notifications"
  end

  test "dashboard shows the install app prompt card" do
    sign_in!

    get dashboard_path

    assert_response :success
    assert_select "[data-controller='install-prompt']", count: 1
    assert_select "button.ibox-toggle-button[data-action='install-prompt#toggleCollapse'][aria-expanded='true']"
    assert_select "button[data-action='install-prompt#prompt'][hidden]", text: "Install on this device"
    assert_select "a[href='#{install_path}']", text: "Install guide"
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
