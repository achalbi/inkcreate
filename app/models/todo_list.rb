class TodoList < ApplicationRecord
  include DriveRecordExportableChange

  belongs_to :page, optional: true
  belongs_to :notepad_entry, optional: true
  has_many :todo_items, -> { order(position: :asc, created_at: :asc) }, dependent: :destroy

  validates :page_id, uniqueness: true, allow_nil: true
  validates :notepad_entry_id, uniqueness: true, allow_nil: true
  validate :exactly_one_owner

  before_validation :normalize_booleans

  def completed_count
    todo_items.completed.count
  end

  def total_count
    todo_items.count
  end

  def progress_label
    "#{completed_count} / #{total_count} done"
  end

  def display_todo_items
    todo_items.ordered
  end

  def track_manual_reordering!
    return unless manual_reordering_column?
    return if self[:manually_reordered]

    update!(manually_reordered: true)
  end

  def owner
    page || notepad_entry
  end

  private

  def drive_record_export_owner
    owner
  end

  def normalize_booleans
    self.enabled = true if enabled.nil?
    self.hide_completed = false if hide_completed.nil?
    self[:manually_reordered] = false if manual_reordering_column? && self[:manually_reordered].nil?
  end

  def manual_reordering_column?
    has_attribute?(:manually_reordered)
  end

  def exactly_one_owner
    owners = [page_id.presence, notepad_entry_id.presence].compact
    return if owners.one?

    errors.add(:base, "Choose exactly one owner for this to-do list.")
  end
end
