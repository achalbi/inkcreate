class Reminder < ApplicationRecord
  attr_accessor :fire_at_local, :snooze_until_local

  enum :status, {
    pending: 0,
    triggered: 10,
    snoozed: 20,
    dismissed: 30,
    expired: 40
  }, prefix: true

  belongs_to :user
  belongs_to :target, polymorphic: true, optional: true

  validates :title, presence: true
  validates :fire_at, presence: true
  validate :single_todo_item_reminder, if: :todo_item_target?

  scope :scheduled, -> { where(status: [statuses[:pending], statuses[:snoozed]]) }
  scope :upcoming_first, ->(time = Time.current) {
    scheduled.where("fire_at > ?", time).order(fire_at: :asc, created_at: :asc)
  }
  scope :upcoming, ->(time = Time.current) { upcoming_first(time) }
  scope :history, ->(time = Time.current) {
    where(status: [statuses[:triggered], statuses[:dismissed], statuses[:expired]])
      .or(scheduled.where(fire_at: ..time))
  }
  scope :history_recent_first, -> {
    history
      .order(last_triggered_at: :desc, fire_at: :desc, created_at: :desc)
  }
  scope :due, ->(time = Time.current) { scheduled.where(fire_at: ..time).order(fire_at: :asc, created_at: :asc) }

  before_validation :rearm_if_rescheduled
  after_commit :schedule_dispatch, on: %i[create update]

  def standalone?
    target.blank?
  end

  def dispatchable?
    status_pending? || status_snoozed?
  end

  def source_label
    return "Standalone" if standalone?
    return "From to-do" if target.is_a?(TodoItem)

    target_type.to_s.humanize
  end

  def destination_path
    return Rails.application.routes.url_helpers.reminder_path(self) if standalone?

    if target.is_a?(TodoItem)
      owner = target.todo_list.owner

      if owner.is_a?(Page)
        return Rails.application.routes.url_helpers.notebook_chapter_page_path(owner.notebook, owner.chapter, owner)
      end

      if owner.is_a?(NotepadEntry)
        return Rails.application.routes.url_helpers.notepad_entry_path(owner)
      end
    end

    Rails.application.routes.url_helpers.reminder_path(self)
  end

  def dismiss!
    update!(status: :dismissed)
  end

  def snooze!(until_time)
    update!(
      status: :snoozed,
      fire_at: until_time,
      snooze_until: until_time
    )
  end

  private

  def todo_item_target?
    target_type == "TodoItem" && target_id.present?
  end

  def single_todo_item_reminder
    existing_scope = self.class.where(target_type: target_type, target_id: target_id)
    existing_scope = existing_scope.where.not(id: id) if persisted?

    if existing_scope.exists?
      errors.add(:base, "This to-do item already has a reminder.")
    end
  end

  def rearm_if_rescheduled
    return unless persisted?
    return unless will_save_change_to_fire_at?

    self.status = :pending
    self.snooze_until = nil
    self.last_triggered_at = nil
  end

  def schedule_dispatch
    return unless dispatchable?
    return if fire_at.blank?

    Async::Dispatcher.enqueue_reminder(id, fire_at: fire_at)
  end
end
