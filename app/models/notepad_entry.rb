class NotepadEntry < ApplicationRecord
  include RetainsPendingPhotos

  belongs_to :user
  has_many_attached :photos

  validates :entry_date, presence: true
  validate :notes_or_photos_present

  scope :recent_first, -> { order(entry_date: :desc, created_at: :desc) }

  before_validation :generate_title_if_blank

  def display_title
    title.presence || generated_title
  end

  private

  def generate_title_if_blank
    return if title.present?

    self.title = generated_title if notes.present? || entry_date.present?
  end

  def generated_title
    "#{title_prefix} - Page #{page_sequence_number}"
  end

  def title_prefix
    notes_excerpt.presence || dated_title
  end

  def notes_excerpt
    notes.to_s.squish.truncate(60, separator: " ")
  end

  def dated_title
    return "Untitled page" if entry_date.blank?

    entry_date.strftime("%A, %b %-d")
  end

  def page_sequence_number
    return 1 if user.blank? || entry_date.blank?

    scope = user.notepad_entries.where(entry_date: entry_date)
    scope = scope.where.not(id: id) if persisted?
    scope.count + 1
  end

  def notes_or_photos_present
    return if notes.present? || photos.attached? || pending_photo_blobs.any?

    errors.add(:base, "Add notes or at least one photo.")
  end
end
