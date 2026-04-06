class AppSetting < ApplicationRecord
  OCR_MODES = %w[manual].freeze
  BACKUP_PROVIDERS = %w[google_drive].freeze
  PRIVACY_DEFAULTS = {
    "allow_ocr_processing" => true,
    "include_photos_in_backups" => true,
    "keep_deleted_chapters_recoverable" => true,
    "clear_backup_metadata_on_disconnect" => true
  }.freeze

  belongs_to :user

  before_validation :normalize_privacy_options!

  validates :ocr_mode, inclusion: { in: OCR_MODES }
  validates :backup_provider, inclusion: { in: BACKUP_PROVIDERS }, allow_blank: true

  def google_drive_backup?
    backup_enabled? && backup_provider == "google_drive"
  end

  def merged_privacy_options
    PRIVACY_DEFAULTS.merge(privacy_options.to_h.stringify_keys.slice(*PRIVACY_DEFAULTS.keys))
  end

  def allow_ocr_processing?
    privacy_option_enabled?("allow_ocr_processing")
  end

  def include_photos_in_backups?
    privacy_option_enabled?("include_photos_in_backups")
  end

  def keep_deleted_chapters_recoverable?
    privacy_option_enabled?("keep_deleted_chapters_recoverable")
  end

  def clear_backup_metadata_on_disconnect?
    privacy_option_enabled?("clear_backup_metadata_on_disconnect")
  end

  private

  def normalize_privacy_options!
    raw_options = privacy_options.to_h.stringify_keys

    self.privacy_options = PRIVACY_DEFAULTS.keys.index_with do |key|
      if raw_options.key?(key)
        ActiveModel::Type::Boolean.new.cast(raw_options[key])
      else
        PRIVACY_DEFAULTS.fetch(key)
      end
    end
  end

  def privacy_option_enabled?(key)
    ActiveModel::Type::Boolean.new.cast(merged_privacy_options.fetch(key))
  end
end
