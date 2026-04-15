class TodoItem < ApplicationRecord
  include DriveRecordExportableChange

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
  after_create :prepend_into_list, if: :prepend_on_create?

  delegate :owner, to: :todo_list
  delegate :user, to: :owner

  def position=(value)
    @position_explicitly_assigned = true unless value.nil?
    super
  end

  def toggle_completion!
    update!(completed: !completed)
  end

  private

  def drive_record_export_owner
    owner
  end

  def normalize_content
    self.content = content.to_s.squish
  end

  def assign_position
    if @position_explicitly_assigned
      @prepend_on_create = false
      return
    end

    self[:position] = 1
    @prepend_on_create = true
  end

  def sync_completed_at
    self.completed_at = completed? ? (completed_at || Time.current) : nil
  end

  def prepend_on_create?
    @prepend_on_create == true
  end

  def prepend_into_list
    todo_list.todo_items.where.not(id: id).update_all(["position = position + 1, updated_at = ?", Time.current])
  end
end
