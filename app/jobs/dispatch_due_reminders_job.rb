class DispatchDueRemindersJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :polynomially_longer, attempts: 8

  def perform(reminder_id = nil)
    reminder_scope(reminder_id).find_each do |reminder|
      dispatch_reminder(reminder)
    end
  end

  private

  def reminder_scope(reminder_id)
    return Reminder.where(id: reminder_id) if reminder_id.present?

    Reminder.due
  end

  def dispatch_reminder(reminder)
    reminder.with_lock do
      reminder.reload

      return unless reminder.dispatchable?
      return if reminder.fire_at.blank? || reminder.fire_at > Time.current

      reminder.update!(
        status: :triggered,
        last_triggered_at: Time.current,
        snooze_until: nil
      )
    end

    reminder.user.enabled_devices_for_push.find_each do |device|
      DeliverReminderPushJob.perform_later(reminder.id, device.id)
    end
  end
end
