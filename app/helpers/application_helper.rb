module ApplicationHelper
  def reminder_relative_time(reminder)
    distance = distance_of_time_in_words(Time.current, reminder.fire_at)

    if reminder.fire_at.future?
      "in #{distance}"
    else
      "#{distance} ago"
    end
  end

  def reminder_source_label(reminder)
    if reminder.target.is_a?(TodoItem)
      "From to-do: #{reminder.target.content}"
    else
      "Standalone"
    end
  end

  def reminder_fire_at_local_value(reminder)
    reminder.fire_at&.in_time_zone&.strftime("%Y-%m-%dT%H:%M")
  end

  def voice_note_duration_label(duration_seconds)
    total_seconds = duration_seconds.to_i
    hours = total_seconds / 3600
    minutes = (total_seconds % 3600) / 60
    seconds = total_seconds % 60

    if hours.positive?
      format("%d:%02d:%02d", hours, minutes, seconds)
    else
      format("%02d:%02d", minutes, seconds)
    end
  end
end
