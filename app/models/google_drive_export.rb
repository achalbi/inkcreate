class GoogleDriveExport < ApplicationRecord
  enum :status, {
    pending: 0,
    running: 10,
    succeeded: 20,
    failed: 30
  }, prefix: true

  belongs_to :user
  belongs_to :exportable, polymorphic: true

  validates :remote_photo_file_ids, presence: true
end
