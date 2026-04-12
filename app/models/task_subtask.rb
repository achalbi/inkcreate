class TaskSubtask < ApplicationRecord
  belongs_to :task

  validates :title, presence: true

  scope :ordered, -> { order(:position) }

  def mark_complete!
    update!(completed: true, completed_at: Time.current)
  end

  def mark_open!
    update!(completed: false, completed_at: nil)
  end
end
