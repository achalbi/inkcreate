class SyncJob < ApplicationRecord
  enum :status, {
    pending: 0,
    running: 10,
    synced: 20,
    failed: 30,
    conflict: 40
  }, prefix: true

  belongs_to :user

  validates :syncable_type, :syncable_id, :job_type, presence: true

  scope :recent_first, -> { order(created_at: :desc) }
end
