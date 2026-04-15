require "test_helper"
require "nokogiri"

class AdminNavigationTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(
      email: "admin@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :admin
    )
  end

  test "admin dashboard links resolve to admin pages" do
    drive_user = User.create!(
      email: "drive-user@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )
    entry = drive_user.notepad_entries.create!(
      title: "Drive export source",
      notes: "Ready for admin visibility.",
      entry_date: Date.current
    )
    drive_user.google_drive_exports.create!(
      exportable: entry,
      status: :failed,
      error_message: "Drive export failed",
      remote_photo_file_ids: {}
    )
    capture = drive_user.captures.create!(
      title: "Operations capture",
      original_filename: "ops.jpg",
      content_type: "image/jpeg",
      byte_size: 1024,
      storage_bucket: "test-bucket",
      storage_object_key: "users/#{drive_user.id}/uploads/test/ops.jpg",
      page_type: "blank"
    )
    drive_user.backup_records.create!(
      capture: capture,
      provider: "google_drive",
      status: :failed,
      error_message: "Backup package upload failed"
    )
    drive_user.drive_syncs.create!(
      capture: capture,
      drive_folder_id: "drive-folder-123",
      status: :failed,
      mode: :automatic,
      error_message: "Drive sync package failed",
      metadata: { "package_type" => "capture", "folder_path" => ["Captures", "Operations capture (abcd1234)"] }
    )

    sign_in_as(@admin)

    get admin_dashboard_path

    assert_response :success
    assert_select ".admin-dashboard-hero", 1
    assert_select ".admin-dashboard-highlight", 4
    assert_select ".admin-dashboard-mobile-list .admin-dashboard-user-card", minimum: 1
    assert_select "#page-loader"
    assert_select "link[href*='/inapp/page_loader.css?v=']"
    assert_select "script[src*='/scripts/page_loader.js?v=']"
    assert_select "a[href='#{admin_users_path}']"
    assert_select "a[href='#{admin_captures_path}']"
    assert_select "a[href='#{admin_operations_path}']"
    assert_select "a[href='#{dashboard_path}']"

    get admin_captures_path
    assert_response :success
    assert_select "h1", /Review every notebook page moving through the system/

    get admin_operations_path
    assert_response :success
    assert_select "h1", /Watch OCR, sync, and backup queues before they become support issues/
    assert_select "h6", text: "Record exports"
    assert_select "h2", text: "Recent record exports"
    assert_select "td", text: /Drive export source/
    assert_select "td", text: /Backup package upload failed/
    assert_select "td", text: /Drive sync package failed/
  end

  private

  def sign_in_as(user)
    get browser_sign_in_path

    post browser_sign_in_path, params: {
      authenticity_token: authenticity_token_for(browser_sign_in_path),
      user: { email: user.email, password: "Password123!" }
    }

    assert_redirected_to admin_dashboard_path
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
