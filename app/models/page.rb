class Page < ApplicationRecord
  include RetainsPendingPhotos
  include RichNotes

  attr_accessor :pending_voice_note_uploads,
    :pending_voice_note_duration_seconds,
    :pending_voice_note_recorded_ats,
    :pending_todo_item_contents,
    :pending_todo_list_enabled,
    :pending_todo_list_hide_completed

  belongs_to :chapter
  has_many_attached :photos
  has_many :voice_notes, -> { order(recorded_at: :asc, created_at: :asc) }, dependent: :destroy
  has_one :todo_list, dependent: :destroy
  has_many :todo_items, through: :todo_list
  has_one :google_drive_export, as: :exportable, dependent: :destroy

  # Titles stay required because pages appear in nested notebook lists,
  # but we generate one from the content/date when the user leaves it blank.
  validates :title, presence: true
  validates :position, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validate :content_present

  scope :ordered, -> { order(position: :asc, created_at: :asc) }

  before_validation :assign_position, on: :create
  before_validation :sync_title_with_page_number
  after_update_commit :rename_google_drive_folder, if: :google_drive_folder_rename_required?

  delegate :notebook, to: :chapter
  delegate :user, to: :notebook

  def display_title
    title.presence || titled_with_page_number(title_prefix)
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

  def sync_title_with_page_number
    self.title = titled_with_page_number(title_without_suffix.presence || title_prefix)
  end

  def title_prefix
    notes_excerpt.presence || captured_on_title.presence || "Untitled"
  end

  def title_without_suffix
    title.to_s.sub(/\s*-\s*Page\s+\d+\z/i, "").strip
  end

  def titled_with_page_number(prefix)
    "#{prefix.presence || "Untitled"} - Page #{title_page_number}"
  end

  def notes_excerpt
    plain_notes.squish.truncate(60, separator: " ")
  end

  def captured_on_title
    return if captured_on.blank?

    captured_on.strftime("%b %-d, %Y")
  end

  def title_page_number
    position.presence || (chapter&.pages&.maximum(:position) || 0) + 1
  end

  def assign_position
    self.position ||= (chapter&.pages&.maximum(:position) || 0) + 1
  end

  def content_present
    return if plain_notes.present?
    return if photos.attached? || pending_photo_blobs.any?
    return if voice_notes_available? && (voice_notes.exists? || pending_voice_note_uploads.any?)
    return if todo_items_present?

    errors.add(:base, "Add notes, a photo, a voice note, or a to-do item.")
  end

  def todo_items_present?
    return false unless todo_lists_available?

    if todo_list&.enabled? && todo_list.todo_items.exists?
      return true
    end

    pending_todo_list_enabled? && pending_todo_item_contents.any?
  end

  def voice_notes_available?
    VoiceNote.schema_ready?
  end

  def todo_lists_available?
    TodoList.schema_ready? && TodoItem.schema_ready?
  end

  def google_drive_folder_rename_required?
    (saved_change_to_title? || saved_change_to_position?) && user.google_drive_ready?
  end

  def rename_google_drive_folder
    Drive::RenameRecordFolder.new(record: self).call
  end
end
