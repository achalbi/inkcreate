class TodoItem < ApplicationRecord
  belongs_to :todo_list
  has_one :reminder, as: :target, dependent: :destroy

  validates :content, presence: true
  validates :position, presence: true, numericality: { only_integer: true, greater_than: 0 }

  scope :ordered, -> { order(position: :asc, created_at: :asc) }
  scope :completed, -> { where(completed: true) }
  scope :pending, -> { where(completed: false) }

  before_validation :normalize_content
  before_validation :assign_position, on: :create
  before_save :sync_completed_at

  delegate :owner, to: :todo_list
  delegate :user, to: :owner

  def toggle_completion!
    update!(completed: !completed)
  end

  private

  def normalize_content
    self.content = content.to_s.squish
  end

  def assign_position
    self.position ||= (todo_list&.todo_items&.maximum(:position) || 0) + 1
  end

  def sync_completed_at
    self.completed_at = completed? ? (completed_at || Time.current) : nil
  end
end
