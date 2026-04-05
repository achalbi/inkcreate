class CaptureTag < ApplicationRecord
  belongs_to :capture
  belongs_to :tag

  validates :tag_id, uniqueness: { scope: :capture_id }
end
