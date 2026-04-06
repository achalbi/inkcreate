class Chapter < ApplicationRecord
  belongs_to :notebook
  has_many :pages, -> { order(position: :asc, created_at: :asc) }, dependent: :destroy

  validates :title, presence: true
  validates :position, presence: true, numericality: { only_integer: true, greater_than: 0 }

  scope :kept, -> { where(deleted_at: nil) }
  scope :deleted, -> { where.not(deleted_at: nil) }
  scope :ordered, -> { order(position: :asc, created_at: :asc) }

  before_validation :assign_position, on: :create
  after_update_commit :rename_google_drive_folder, if: :saved_change_to_title?

  delegate :user, to: :notebook

  def soft_deleted?
    deleted_at.present?
  end

  def soft_delete!
    update!(deleted_at: deleted_at || Time.current)
  end

  def restore!
    update!(deleted_at: nil)
  end

  private

  def assign_position
    self.position ||= (notebook&.all_chapters&.maximum(:position) || 0) + 1
  end

  def rename_google_drive_folder
    return unless user.google_drive_ready?

    previous_title = title_before_last_save
    return if previous_title.blank? || previous_title == title

    Drive::RenameChapterFolder.new(chapter: self, previous_title: previous_title).call
  end
end
