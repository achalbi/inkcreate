class BackupRecord < ApplicationRecord
  enum :status, {
    pending: 0,
    running: 10,
    uploaded: 20,
    failed: 30
  }, prefix: true

  belongs_to :user
  belongs_to :capture

  validates :provider, presence: true

  scope :recent_first, -> { order(updated_at: :desc, created_at: :desc) }
  scope :latest_per_capture_provider, lambda {
    deduped_ids = except(:select, :order)
      .select("DISTINCT ON (backup_records.capture_id, backup_records.provider) backup_records.id")
      .order(Arel.sql("backup_records.capture_id, backup_records.provider, backup_records.updated_at DESC, backup_records.created_at DESC"))

    where(id: deduped_ids)
  }
end
