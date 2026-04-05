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
end
