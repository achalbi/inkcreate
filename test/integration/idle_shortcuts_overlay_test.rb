require "test_helper"
require "nokogiri"

class IdleShortcutsOverlayTest < ActionDispatch::IntegrationTest
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

  test "workspace pages render the shared launcher overlay" do
    sign_in!

    entry = @user.notepad_entries.create!(
      title: "Shortcut page",
      notes: "Jump around this daily page.",
      entry_date: Date.current
    )

    get notepad_entry_path(entry)

    assert_response :success
    assert_select ".idle-shortcuts-backdrop[data-controller='idle-shortcuts'][data-idle-shortcuts-storage-key-value='workspace-launcher']", count: 1
    assert_select ".idle-shortcuts-grid--launcher .idle-shortcuts-card", count: 6
    assert_select ".idle-shortcuts-card", text: /Photo/
    assert_select ".idle-shortcuts-card[data-idle-shortcuts-command='open-modal'][data-idle-shortcuts-modal-id='workspace-voice-note-modal']", text: /Voice notes/
    assert_select ".idle-shortcuts-card[data-idle-shortcuts-command='open-modal'][data-idle-shortcuts-modal-id='workspace-scan-modal']", text: /Scan documents/
    assert_select ".idle-shortcuts-card[href='#{tasks_path}']", text: /Tasks/
    assert_select ".idle-shortcuts-card[data-idle-shortcuts-command='open-modal'][data-idle-shortcuts-modal-id='workspace-new-reminder-modal']", text: /New reminder/
    assert_select ".idle-shortcuts-continue", text: "Continue →"
  end

  test "workspace launcher exposes photo capture and shared reminder modal from tasks page" do
    sign_in!

    get tasks_path

    assert_response :success
    assert_select ".idle-shortcuts-card-wrap[data-controller='quick-capture']", count: 1
    assert_select "#workspace-new-reminder-modal", count: 1
    assert_select "#workspace-scan-modal", count: 1
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
