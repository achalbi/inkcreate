class Task < ApplicationRecord
  PRIORITY_ORDER = { "urgent" => 0, "high" => 1, "medium" => 2, "low" => 3 }.freeze
  SEVERITY_ORDER = { "blocker" => 0, "major" => 1, "minor" => 2, "trivial" => 3 }.freeze
  RECURRENCES = %w[none daily weekly monthly custom].freeze
  LINK_TYPES = %w[notebook chapter page voice photo todo].freeze

  enum :priority, {
    low: 0,
    medium: 10,
    high: 20,
    urgent: 30
  }, prefix: true

  enum :severity, {
    trivial: 0,
    minor: 10,
    major: 20,
    blocker: 30
  }, prefix: true

  belongs_to :user
  belongs_to :capture, optional: true
  belongs_to :project, optional: true
  belongs_to :daily_log, optional: true
  has_many :task_subtasks, -> { order(:position) }, dependent: :destroy

  validates :title, presence: true
  validates :reminder_recurrence, inclusion: { in: RECURRENCES }, allow_blank: true
  validates :link_type, inclusion: { in: LINK_TYPES }, allow_blank: true

  scope :open, -> { where(completed: false) }
  scope :done, -> { where(completed: true) }
  scope :recent_first, -> { order(created_at: :desc) }
  scope :priority_first, -> { order(Arel.sql("CASE priority WHEN 30 THEN 0 WHEN 20 THEN 1 WHEN 10 THEN 2 ELSE 3 END")) }
  scope :due_soon, -> { where(completed: false).where(due_date: ..7.days.from_now.to_date).order(:due_date) }
  scope :overdue, -> { open.where(due_date: ..Date.yesterday) }
  scope :due_today, -> { open.where(due_date: Date.current) }
  scope :with_reminder, -> { where.not(reminder_at: nil) }
  scope :tagged_with, ->(tag) { where("tags LIKE ?", "%#{sanitize_sql_like(tag)}%") }

  def mark_complete!
    update!(completed: true, completed_at: Time.current)
  end

  def mark_open!
    update!(completed: false, completed_at: nil)
  end

  def tags_array
    return [] if tags.blank?
    JSON.parse(tags)
  rescue JSON::ParserError
    []
  end

  def tags_array=(arr)
    self.tags = arr.to_json
  end

  def add_tag(tag)
    list = tags_array
    list << tag.strip unless list.include?(tag.strip) || tag.blank?
    self.tags = list.to_json
  end

  def remove_tag(tag)
    self.tags = (tags_array - [ tag ]).to_json
  end

  def has_link?
    link_type.present?
  end

  def overdue?
    due_date.present? && !completed? && due_date < Date.current
  end

  def due_today?
    due_date == Date.current
  end

  def subtask_progress
    total = task_subtasks.size
    return [0, 0] if total.zero?
    done = task_subtasks.count(&:completed)
    [done, total]
  end
end
