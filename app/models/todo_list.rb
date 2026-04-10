class TodoList < ApplicationRecord
  belongs_to :page
  has_many :todo_items, -> { order(position: :asc, created_at: :asc) }, dependent: :destroy

  validates :page_id, uniqueness: true

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

  private

  def normalize_booleans
    self.enabled = true if enabled.nil?
    self.hide_completed = false if hide_completed.nil?
  end
end
