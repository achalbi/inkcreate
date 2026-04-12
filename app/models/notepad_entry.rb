class NotepadEntry < ApplicationRecord
  include RetainsPendingPhotos
  include RichNotes

  attr_accessor :pending_voice_note_uploads,
    :pending_voice_note_duration_seconds,
    :pending_voice_note_recorded_ats,
    :pending_todo_item_contents,
    :pending_todo_list_enabled,
    :pending_todo_list_hide_completed

  belongs_to :user
  has_many_attached :photos
  has_many :voice_notes, -> { order(recorded_at: :asc, created_at: :asc) }, dependent: :destroy
  has_one :todo_list, dependent: :destroy
  has_many :todo_items, through: :todo_list
  has_many :scanned_documents, dependent: :destroy
  has_one :google_drive_export, as: :exportable, dependent: :destroy

  validates :entry_date, presence: true
  validate :content_present

  scope :recent_first, -> { order(entry_date: :desc, created_at: :desc) }

  before_validation :generate_title_if_blank

  def display_title
    title.presence || generated_title
  end

  def pending_voice_note_uploads
    Array(@pending_voice_note_uploads).reject(&:blank?)
  end

  def pending_voice_note_duration_seconds
    Array(@pending_voice_note_duration_seconds).map(&:presence)
  end

  def pending_voice_note_recorded_ats
    Array(@pending_voice_note_recorded_ats).map(&:presence)
  end

  def pending_todo_item_contents
    Array(@pending_todo_item_contents).filter_map { |content| content.to_s.squish.presence }
  end

  def pending_todo_list_enabled?
    ActiveModel::Type::Boolean.new.cast(@pending_todo_list_enabled) == true
  end

  def pending_todo_list_hide_completed?
    ActiveModel::Type::Boolean.new.cast(@pending_todo_list_hide_completed) == true
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
    plain_notes.squish.truncate(60, separator: " ")
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

  def content_present
    return if plain_notes.present?
    return if photos.attached? || pending_photo_blobs.any?
    return if voice_notes_available? && (voice_notes.exists? || pending_voice_note_uploads.any?)
    return if todo_items_present?

    errors.add(:base, "Add notes, a photo, a voice note, or a to-do item.")
  end

  def voice_notes_available?
    VoiceNote.notepad_entries_supported?
  end

  def todo_items_present?
    return false unless todo_lists_available?

    if todo_list&.enabled? && todo_list.todo_items.exists?
      return true
    end

    pending_todo_list_enabled?
  end

  def todo_lists_available?
    TodoList.schema_ready? && TodoItem.schema_ready?
  end
end
