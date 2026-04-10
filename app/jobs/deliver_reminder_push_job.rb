class DeliverReminderPushJob < ApplicationJob
  queue_as :low

  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  def perform(reminder_id, device_id)
    reminder = Reminder.find(reminder_id)
    device = reminder.user.devices.find(device_id)
    return unless device.push_enabled?
    return unless WebPushDeliverer.configured?

    Current.request_id = job_id
    Current.user = reminder.user
    Current.device = device

    WebPushDeliverer.deliver(device: device, payload: payload_for(reminder))
  ensure
    Current.reset
  end

  private

  def payload_for(reminder)
    {
      title: reminder.title,
      body: reminder.note.presence || default_body(reminder),
      url: reminder.destination_path,
      tag: "reminder-#{reminder.id}",
      reminder_id: reminder.id,
      source: reminder.source_label
    }
  end

  def default_body(reminder)
    if reminder.standalone?
      "Your reminder is due now."
    else
      "#{reminder.source_label} is due now."
    end
  end
end
