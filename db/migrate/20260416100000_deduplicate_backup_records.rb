class DeduplicateBackupRecords < ActiveRecord::Migration[8.1]
  class BackupRecord < ActiveRecord::Base
    self.table_name = "backup_records"
  end

  class DriveSync < ActiveRecord::Base
    self.table_name = "drive_syncs"
  end

  def up
    say_with_time "Deduplicating backup records" do
      duplicate_groups = BackupRecord.group(:capture_id, :provider).having("COUNT(*) > 1").count

      duplicate_groups.each_key do |capture_id, provider|
        deduplicate_group(capture_id:, provider:)
      end

      duplicate_groups.size
    end
  end

  def down
    # Irreversible data cleanup.
  end

  private

  def deduplicate_group(capture_id:, provider:)
    records = BackupRecord.where(capture_id: capture_id, provider: provider).order(updated_at: :desc, created_at: :desc).to_a
    return if records.size < 2

    keep_record = choose_keep_record(records, capture_id: capture_id)
    duplicate_records = records.reject { |record| record.id == keep_record.id }
    duplicate_ids = duplicate_records.map(&:id)

    keep_record.update_columns(merged_attributes(records, keep_record))
    repoint_drive_syncs(capture_id: capture_id, duplicate_ids: duplicate_ids, keep_id: keep_record.id)
    BackupRecord.where(id: duplicate_ids).delete_all
  end

  def choose_keep_record(records, capture_id:)
    active_backup_record_ids = DriveSync.where(capture_id: capture_id, status: [0, 10]).order(updated_at: :desc, created_at: :desc).filter_map do |drive_sync|
      drive_sync.metadata.to_h["backup_record_id"].presence
    end

    active_backup_record_ids.each do |backup_record_id|
      matching_record = records.find { |record| record.id == backup_record_id }
      return matching_record if matching_record.present?
    end

    records.first
  end

  def merged_attributes(records, keep_record)
    newest_record = records.find { |record| record.remote_file_id.present? || record.remote_path.present? || record.error_message.present? } || keep_record
    merged_metadata = records.reverse.reduce({}) { |metadata, record| metadata.merge(record.metadata.to_h) }

    {
      remote_file_id: newest_record.remote_file_id.presence || keep_record.remote_file_id,
      remote_path: newest_record.remote_path.presence || keep_record.remote_path,
      last_success_at: records.map(&:last_success_at).compact.max || keep_record.last_success_at,
      last_attempt_at: records.map(&:last_attempt_at).compact.max || keep_record.last_attempt_at,
      error_message: keep_record.error_message.presence || newest_record.error_message,
      metadata: merged_metadata,
      updated_at: records.map(&:updated_at).compact.max || keep_record.updated_at
    }
  end

  def repoint_drive_syncs(capture_id:, duplicate_ids:, keep_id:)
    return if duplicate_ids.empty?

    duplicate_lookup = duplicate_ids.map(&:to_s)

    DriveSync.where(capture_id: capture_id).find_each do |drive_sync|
      backup_record_id = drive_sync.metadata.to_h["backup_record_id"].to_s
      next unless duplicate_lookup.include?(backup_record_id)

      drive_sync.update_columns(metadata: drive_sync.metadata.to_h.merge("backup_record_id" => keep_id))
    end
  end
end
