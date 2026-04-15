require "test_helper"
require "ostruct"

class Ocr::PipelineTest < ActiveSupport::TestCase
  def build_user(email:)
    user = User.create!(
      email: email,
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )
    user.update!(
      google_drive_connected_at: Time.current,
      google_drive_refresh_token: "refresh-token",
      google_drive_folder_id: "drive-root-folder"
    )
    user.ensure_app_setting!.update!(
      backup_enabled: true,
      backup_provider: "google_drive",
      privacy_options: user.ensure_app_setting!.privacy_options.merge("include_photos_in_backups" => true)
    )
    user
  end

  def build_capture(user:, title:, drive_sync_mode:)
    page_template = PageTemplate.find_or_create_by!(key: "blank") do |template|
      template.name = "Blank"
      template.description = "Blank page"
    end

    user.captures.create!(
      title: title,
      original_filename: "#{title.parameterize}.jpg",
      content_type: "image/jpeg",
      byte_size: 1024,
      storage_bucket: "test-bucket",
      storage_object_key: "users/#{user.id}/uploads/test/#{title.parameterize}.jpg",
      page_type: "blank",
      page_template: page_template,
      drive_sync_mode: drive_sync_mode,
      backup_status: :local_only
    )
  end

  def build_ocr_job(capture:)
    capture.ocr_jobs.create!(provider: "tesseract", status: :queued)
  end

  def build_provider_result
    OpenStruct.new(
      raw_text: "Quarterly kickoff agenda",
      cleaned_text: "Quarterly kickoff agenda",
      mean_confidence: 0.91,
      language: "eng",
      metadata: { "engine" => "stubbed" }
    )
  end

  test "automatic OCR captures schedule capture package backup through the shared scheduler" do
    user = build_user(email: "ocr-pipeline-auto-backup@example.com")
    capture = build_capture(user: user, title: "OCR automatic", drive_sync_mode: :automatic)
    ocr_job = build_ocr_job(capture: capture)
    pipeline = Ocr::Pipeline.new(ocr_job: ocr_job)
    source_file = Tempfile.new(["ocr-source", ".jpg"])
    processed_file = Tempfile.new(["ocr-processed", ".png"])
    scheduler_calls = []

    pipeline.stub(:download_source_file, source_file) do
      Ocr::ImagePreprocessor.stub(:new, ->(**) { OpenStruct.new(call: processed_file) }) do
        Ocr::ProviderFactory.stub(:build, lambda { |*|
          provider_result = build_provider_result
          Object.new.tap do |provider|
            provider.define_singleton_method(:call) { |**| provider_result }
          end
        }) do
          Backups::ScheduleCaptureBackup.stub(:new, ->(capture:, user:, mode:) {
            scheduler_calls << { capture: capture, user: user, mode: mode }
            OpenStruct.new(call: Backups::ScheduleCaptureBackup::Result.new(backup_record: Object.new))
          }) do
            pipeline.call
          end
        end
      end
    end

    assert_equal 1, scheduler_calls.size
    assert_equal capture, scheduler_calls.first[:capture]
    assert_equal user, scheduler_calls.first[:user]
    assert_equal :automatic, scheduler_calls.first[:mode]
    assert ocr_job.reload.status_succeeded?
    assert capture.reload.ocr_status_completed?
  ensure
    source_file&.close!
    processed_file&.close!
  end

  test "manual OCR captures do not schedule automatic backup export" do
    user = build_user(email: "ocr-pipeline-manual-backup@example.com")
    capture = build_capture(user: user, title: "OCR manual", drive_sync_mode: :manual)
    ocr_job = build_ocr_job(capture: capture)
    pipeline = Ocr::Pipeline.new(ocr_job: ocr_job)
    source_file = Tempfile.new(["ocr-source", ".jpg"])
    processed_file = Tempfile.new(["ocr-processed", ".png"])
    scheduler_calls = []

    pipeline.stub(:download_source_file, source_file) do
      Ocr::ImagePreprocessor.stub(:new, ->(**) { OpenStruct.new(call: processed_file) }) do
        Ocr::ProviderFactory.stub(:build, lambda { |*|
          provider_result = build_provider_result
          Object.new.tap do |provider|
            provider.define_singleton_method(:call) { |**| provider_result }
          end
        }) do
          Backups::ScheduleCaptureBackup.stub(:new, ->(**kwargs) {
            scheduler_calls << kwargs
            OpenStruct.new(call: Backups::ScheduleCaptureBackup::Result.new(backup_record: Object.new))
          }) do
            pipeline.call
          end
        end
      end
    end

    assert_empty scheduler_calls
    assert ocr_job.reload.status_succeeded?
    assert capture.reload.ocr_status_completed?
  ensure
    source_file&.close!
    processed_file&.close!
  end
end
