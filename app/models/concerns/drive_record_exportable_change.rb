module DriveRecordExportableChange
  extend ActiveSupport::Concern

  included do
    before_destroy :store_drive_record_export_owner
    after_create_commit :schedule_drive_record_export_owner_after_create
    after_update_commit :schedule_drive_record_export_owner_after_update
    after_destroy_commit :schedule_drive_record_export_owner_after_destroy
  end

  private

  def schedule_drive_record_export_owner_after_create
    schedule_drive_record_export_owner
  end

  def schedule_drive_record_export_owner_after_update
    return unless drive_record_export_owner_update_worthy?

    schedule_drive_record_export_owner
  end

  def schedule_drive_record_export_owner_after_destroy
    schedule_drive_record_export_owner
  end

  def schedule_drive_record_export_owner
    return if Current.suppress_drive_record_export_callbacks

    owner = @drive_record_export_owner || drive_record_export_owner
    return unless owner&.persisted?

    Drive::ScheduleRecordExport.new(record: owner, sections: drive_record_export_sections).call
  end

  def store_drive_record_export_owner
    @drive_record_export_owner = drive_record_export_owner
  end

  def drive_record_export_owner_update_worthy?
    previous_changes.except("updated_at").present?
  end

  def drive_record_export_sections
    nil
  end
end
