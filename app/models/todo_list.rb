class TodoList < ApplicationRecord
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

  def owner
    page || notepad_entry
  end

  private

  def normalize_booleans
    self.enabled = true if enabled.nil?
    self.hide_completed = false if hide_completed.nil?
  end

  def exactly_one_owner
    owners = [page_id.presence, notepad_entry_id.presence].compact
    return if owners.one?

    errors.add(:base, "Choose exactly one owner for this to-do list.")
  end
end
