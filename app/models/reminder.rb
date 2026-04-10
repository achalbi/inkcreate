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
    return Rails.application.routes.url_helpers.edit_reminder_path(self) if standalone?

    if target.is_a?(TodoItem)
      page = target.todo_list.page
      return Rails.application.routes.url_helpers.notebook_chapter_page_path(page.notebook, page.chapter, page)
    end

    Rails.application.routes.url_helpers.edit_reminder_path(self)
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

  def schedule_dispatch
    return unless dispatchable?
    return if fire_at.blank?

    DispatchDueRemindersJob.set(wait_until: fire_at).perform_later(id)
  end
end
