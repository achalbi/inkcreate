class DriveSync < ApplicationRecord
  enum :status, {
    pending: 0,
    running: 10,
    succeeded: 20,
    failed: 30
  }, prefix: true

  enum :mode, {
    manual: 0,
    automatic: 10
  }, prefix: true

  belongs_to :user
  belongs_to :capture

  validates :drive_folder_id, presence: true
end
