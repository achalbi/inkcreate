require "test_helper"

class AppSettingTest < ActiveSupport::TestCase
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

  test "defaults privacy toggles to enabled" do
    user = build_user(email: "privacy-defaults@example.com")
    app_setting = user.ensure_app_setting!

    assert app_setting.backup_enabled?
    assert_nil app_setting.backup_provider
    assert_not app_setting.google_drive_backup?
    assert_equal "optimized", app_setting.capture_quality_preset
    assert app_setting.allow_ocr_processing?
    assert app_setting.include_photos_in_backups?
    assert app_setting.keep_deleted_chapters_recoverable?
    assert app_setting.clear_backup_metadata_on_disconnect?
  end

  test "normalizes string values for privacy toggles" do
    user = build_user(email: "privacy-normalization@example.com")
    app_setting = user.ensure_app_setting!

    app_setting.update!(
      privacy_options: {
        "allow_ocr_processing" => "false",
        "include_photos_in_backups" => "true",
        "keep_deleted_chapters_recoverable" => "0",
        "clear_backup_metadata_on_disconnect" => "1"
      }
    )

    assert_not app_setting.allow_ocr_processing?
    assert app_setting.include_photos_in_backups?
    assert_not app_setting.keep_deleted_chapters_recoverable?
    assert app_setting.clear_backup_metadata_on_disconnect?
  end

  test "normalizes capture quality preferences" do
    user = build_user(email: "capture-quality-normalization@example.com")
    app_setting = user.ensure_app_setting!

    app_setting.update!(capture_quality_preset: "high")
    assert_equal "high", app_setting.capture_quality_preset

    app_setting.update!(image_quality_preferences: { "capture_quality_preset" => "not-a-real-preset" })
    assert_equal "optimized", app_setting.capture_quality_preset
  end
end
