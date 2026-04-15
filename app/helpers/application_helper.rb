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
    return reminder.fire_at.in_time_zone.strftime("%Y-%m-%dT%H:%M") if reminder.fire_at.present?
    return unless reminder.new_record? && reminder.errors.empty?

    1.hour.from_now.in_time_zone.strftime("%Y-%m-%dT%H:%M")
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

  def google_drive_export_title(google_drive_export)
    exportable = google_drive_export.exportable
    return "#{google_drive_export.exportable_type} ##{google_drive_export.exportable_id}" unless exportable

    exportable.respond_to?(:display_title) ? exportable.display_title : "#{google_drive_export.exportable_type} ##{google_drive_export.exportable_id}"
  end

  def google_drive_export_path(google_drive_export)
    case google_drive_export.exportable
    when Page
      page = google_drive_export.exportable
      notebook_chapter_page_path(page.notebook, page.chapter, page)
    when NotepadEntry
      notepad_entry_path(google_drive_export.exportable)
    end
  end

  def google_drive_export_detail_text(google_drive_export)
    google_drive_export.error_message.presence ||
      google_drive_export.metadata.to_h["folder_path"].presence ||
      google_drive_export.remote_folder_id.presence ||
      "Record export ready."
  end

  def backup_record_detail_text(backup_record)
    return backup_record.error_message if backup_record.error_message.present?

    metadata = backup_record.metadata.to_h
    remote_path = backup_record.remote_path.presence
    remote_path ||= Array(metadata["folder_path"]).presence&.join(" / ")

    if metadata["package_type"] == "capture"
      return "Capture package: #{remote_path}" if remote_path.present?

      return "Capture package ready."
    end

    remote_path.presence || "Backup record ready."
  end

  def drive_sync_detail_text(drive_sync)
    return drive_sync.error_message if drive_sync.error_message.present?

    metadata = drive_sync.metadata.to_h
    remote_path = Array(metadata["folder_path"]).presence&.join(" / ")
    remote_path ||= metadata["remote_folder_id"].presence
    remote_path ||= drive_sync.drive_folder_id.presence

    if metadata["package_type"] == "capture"
      return "Capture package: #{remote_path}" if remote_path.present?

      return "Capture package ready."
    end

    remote_path.presence || "Drive backup export ready."
  end
end
