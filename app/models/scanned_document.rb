class ScannedDocument < ApplicationRecord
  include DriveRecordExportableChange

  belongs_to :user
  belongs_to :page,          optional: true
  belongs_to :notepad_entry, optional: true

  has_one_attached :enhanced_image
  has_one_attached :document_pdf

  validates :title, presence: true
  validates :ocr_engine, inclusion: { in: %w[tesseract google-ml cloud-vision], allow_blank: true }
  validate  :document_assets_attached, on: :create
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
    value = confidence_value
    return "—" unless value

    "#{value.round}%"
  end

  def confidence_class
    value = confidence_value
    return "none" unless value

    pct = value.round
    if pct >= 80 then "high"
    elsif pct >= 50 then "medium"
    else "low"
    end
  end

  def ocr_completed?
    extracted_text.present?
  end

  def ocr_action_label
    ocr_completed? ? "Re-run OCR" : "Run OCR"
  end

  def status_label
    return "#{ocr_engine.presence || "tesseract"} · #{created_at.strftime("%-d %b")}" if ocr_completed?

    "PDF ready · #{created_at.strftime("%-d %b")}"
  end

  private

  def confidence_value
    return ocr_confidence.to_f if ocr_confidence.present?
    return nil if extracted_text.blank?

    ScannedDocuments::ConfidenceEstimator.new(text: extracted_text).call
  end

  def drive_record_export_owner
    page || notepad_entry
  end

  def drive_record_export_sections
    [Drive::RecordExportSections::SCANNED_DOCUMENTS]
  end

  def exactly_one_owner
    if page_id.present? && notepad_entry_id.present?
      errors.add(:base, "cannot belong to both a page and a notepad entry")
    end
  end

  def document_assets_attached
    errors.add(:base, "Scan preview image is missing.") unless enhanced_image.attached?
    errors.add(:base, "Scan PDF is missing.") unless document_pdf.attached?
  end
end
