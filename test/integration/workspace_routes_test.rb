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
      library_path,
      settings_path,
      settings_backup_path,
      settings_privacy_path,
      onboarding_path,
      install_path
    ].each do |path|
      get path
      assert_response :success, "Expected #{path} to render successfully"
    end

    get dashboard_path
    assert_select "#sidebar"
    assert_select "#topbar"
    assert_select "link[href*='/inapp/inapp_workspace.css?v=']"
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

    get settings_backup_path

    patch settings_backup_path, params: {
      authenticity_token: authenticity_token_for(settings_backup_path),
      app_setting: { backup_enabled: "false", backup_provider: "" }
    }

    follow_redirect!

    assert_response :success
    assert_select ".workspace-header .flash-banner.notice", text: /Backup settings updated/
  end

  private

  def sign_in!
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
