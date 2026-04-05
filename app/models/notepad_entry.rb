class NotepadEntry < ApplicationRecord
  belongs_to :user
  has_many_attached :photos

  validates :entry_date, presence: true
  validate :title_or_notes_present

  scope :recent_first, -> { order(entry_date: :desc, created_at: :desc) }

  def display_title
    title.presence || "Untitled entry"
  end

  private

  def title_or_notes_present
    return if title.present? || notes.present?

    errors.add(:base, "Add a title or notes for this entry.")
  end
end
