require "test_helper"
require "nokogiri"
require "tempfile"

class AttachmentFlowTest < ActionDispatch::IntegrationTest
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
      email: "attachments@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )

    @project = @user.projects.create!(title: "Capture context")
    @daily_log = @user.daily_logs.create!(entry_date: Date.current, title: "Today")
    @capture = @user.captures.create!(
      project: @project,
      daily_log: @daily_log,
      title: "Notebook page",
      page_type: "blank",
      original_filename: "capture.jpg",
      content_type: "image/jpeg",
      byte_size: 1024,
      storage_bucket: "test-bucket",
      storage_object_key: "users/#{@user.id}/uploads/test/capture.jpg",
      status: :uploaded,
      ocr_status: :not_started,
      ai_status: :not_started,
      backup_status: :local_only,
      sync_status: :synced
    )
  end

  test "signed in user can upload a file attachment to a capture" do
    sign_in!

    tempfile = Tempfile.new(["inkcreate-attachment", ".txt"])
    tempfile.write("Reusable notebook capture context")
    tempfile.rewind
    upload = Rack::Test::UploadedFile.new(tempfile.path, "text/plain", original_filename: "context.txt")
    get capture_path(@capture)

    assert_difference -> { @capture.attachments.count }, +1 do
      post capture_attachments_path(@capture), params: {
        authenticity_token: authenticity_token_for(capture_attachments_path(@capture)),
        attachment: {
          title: "Context file",
          file: upload
        }
      }
    end

    attachment = @capture.attachments.recent_first.first

    assert_redirected_to capture_path(@capture)
    assert_equal "file", attachment.attachment_type
    assert attachment.asset.attached?
    assert_equal "context.txt", attachment.asset.filename.to_s
  ensure
    tempfile&.close!
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
