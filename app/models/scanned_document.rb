class ScannedDocument < ApplicationRecord
  belongs_to :user
  belongs_to :page,          optional: true
  belongs_to :notepad_entry, optional: true

  has_one_attached :enhanced_image

  validates :title, presence: true
  validates :ocr_engine, inclusion: { in: %w[tesseract google-ml cloud-vision], allow_blank: true }
  validate  :exactly_one_owner

  scope :recent_first, -> { order(created_at: :desc) }

  def tags_array
    return [] if tags.blank?
    JSON.parse(tags)
  rescue JSON::ParserError
    []
  end

  def tags_array=(arr)
    self.tags = arr.to_json
  end

  def confidence_label
    return "—" unless ocr_confidence
    pct = ocr_confidence.round
    if pct >= 80
      "🟢 #{pct}%"
    elsif pct >= 50
      "🟡 #{pct}%"
    else
      "🔴 #{pct}%"
    end
  end

  def confidence_class
    return "conf-mid" unless ocr_confidence
    pct = ocr_confidence.round
    if pct >= 80 then "conf-high"
    elsif pct >= 50 then "conf-mid"
    else "conf-low"
    end
  end

  private

  def exactly_one_owner
    if page_id.present? && notepad_entry_id.present?
      errors.add(:base, "cannot belong to both a page and a notepad entry")
    end
  end
end
