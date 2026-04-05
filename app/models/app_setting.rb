class AppSetting < ApplicationRecord
  OCR_MODES = %w[manual].freeze
  BACKUP_PROVIDERS = %w[google_drive].freeze

  belongs_to :user

  validates :ocr_mode, inclusion: { in: OCR_MODES }
  validates :backup_provider, inclusion: { in: BACKUP_PROVIDERS }, allow_blank: true

  def google_drive_backup?
    backup_enabled? && backup_provider == "google_drive"
  end
end
