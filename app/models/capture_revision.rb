class CaptureRevision < ApplicationRecord
  belongs_to :capture

  validates :revision_number, presence: true, uniqueness: { scope: :capture_id }

  scope :recent_first, -> { order(revision_number: :desc) }
end
