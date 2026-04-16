module DriveRecordExportScheduling
  extend ActiveSupport::Concern

  private

  def schedule_drive_export(record, sections: nil)
    Drive::ScheduleRecordExport.new(record: record, sections: sections).call
  end

  def with_deferred_drive_record_export(record, sections: nil)
    with_suppressed_drive_record_export_callbacks do
      yield
    end

    schedule_drive_export(record, sections: sections)
  end

  def with_suppressed_drive_record_export_callbacks
    previous_value = Current.suppress_drive_record_export_callbacks
    Current.suppress_drive_record_export_callbacks = true
    yield
  ensure
    Current.suppress_drive_record_export_callbacks = previous_value
  end
end
