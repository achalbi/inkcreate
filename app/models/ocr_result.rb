class OcrResult < ApplicationRecord
  belongs_to :capture
  belongs_to :ocr_job

  validates :provider, presence: true
end
