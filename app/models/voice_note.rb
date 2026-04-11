class VoiceNote < ApplicationRecord
  MAX_DURATION_SECONDS = 120.minutes.to_i

  belongs_to :page, optional: true
  belongs_to :notepad_entry, optional: true
  has_one_attached :audio

  validates :audio, presence: true
  validates :duration_seconds, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_DURATION_SECONDS }
  validates :byte_size, numericality: { greater_than: 0, less_than_or_equal_to: 512.megabytes }
  validates :mime_type, presence: true
  validates :recorded_at, presence: true
  validate :attachable_present

  before_validation :sync_audio_metadata

  scope :chronological, -> { reorder(recorded_at: :asc, created_at: :asc) }
  scope :recent_first, -> { reorder(created_at: :desc, recorded_at: :desc) }

  def self.notepad_entries_supported?
    schema_ready? && column_names.include?("notepad_entry_id")
  end

  private

  def sync_audio_metadata
    return unless audio.attached?

    self.byte_size = audio.blob.byte_size if byte_size.blank? || byte_size.zero?
    self.mime_type = audio.blob.content_type.to_s if mime_type.blank?
    self.recorded_at ||= Time.current
  end

  def attachable_present
    attachable_count = [page_id.present?, notepad_entry_id.present?].count(true)
    return if attachable_count == 1

    errors.add(:base, "Voice note must belong to a page or notepad entry.")
  end
end
