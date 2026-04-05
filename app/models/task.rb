class Task < ApplicationRecord
  enum :priority, {
    low: 0,
    medium: 10,
    high: 20,
    urgent: 30
  }, prefix: true

  belongs_to :user
  belongs_to :capture, optional: true
  belongs_to :project, optional: true
  belongs_to :daily_log, optional: true

  validates :title, presence: true

  scope :open, -> { where(completed: false) }
  scope :recent_first, -> { order(created_at: :desc) }
  scope :due_soon, -> { where(completed: false).where(due_date: ..7.days.from_now.to_date).order(:due_date) }

  def mark_complete!
    update!(completed: true, completed_at: Time.current)
  end
end
