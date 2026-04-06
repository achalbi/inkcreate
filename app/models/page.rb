class Page < ApplicationRecord
  include RetainsPendingPhotos

  belongs_to :chapter
  has_many_attached :photos
  has_one :google_drive_export, as: :exportable, dependent: :destroy

  # Titles stay required because pages appear in nested notebook lists,
  # but we generate one from the content/date when the user leaves it blank.
  validates :title, presence: true
  validates :position, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validate :notes_or_photos_present

  scope :ordered, -> { order(position: :asc, created_at: :asc) }

  before_validation :assign_position, on: :create
  before_validation :sync_title_with_page_number
  after_update_commit :rename_google_drive_folder, if: :google_drive_folder_rename_required?

  delegate :notebook, to: :chapter
  delegate :user, to: :notebook

  def display_title
    title.presence || titled_with_page_number(title_prefix)
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
    notes.to_s.squish.truncate(60, separator: " ")
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

  def notes_or_photos_present
    return if notes.present? || photos.attached? || pending_photo_blobs.any?

    errors.add(:base, "Add notes or at least one photo.")
  end

  def google_drive_folder_rename_required?
    (saved_change_to_title? || saved_change_to_position?) && user.google_drive_ready?
  end

  def rename_google_drive_folder
    Drive::RenameRecordFolder.new(record: self).call
  end
end
