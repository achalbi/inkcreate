class OcrJob < ApplicationRecord
  PROVIDERS = %w[tesseract google_vision].freeze

  enum :status, {
    queued: 0,
    running: 10,
    succeeded: 20,
    failed: 30
  }, prefix: true

  belongs_to :capture

  has_many :ocr_results, dependent: :destroy

  validates :provider, inclusion: { in: PROVIDERS }
end
