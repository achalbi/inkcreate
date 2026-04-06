class GoogleDriveExport < ApplicationRecord
  enum :status, {
    pending: 0,
    running: 10,
    succeeded: 20,
    failed: 30
  }, prefix: true

  belongs_to :user
  belongs_to :exportable, polymorphic: true

  validate :remote_photo_file_ids_must_be_a_hash

  private

  def remote_photo_file_ids_must_be_a_hash
    return if remote_photo_file_ids.is_a?(Hash)

    errors.add(:remote_photo_file_ids, "must be a hash")
  end
end
