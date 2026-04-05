class ReferenceLink < ApplicationRecord
  belongs_to :user
  belongs_to :source_capture, class_name: "Capture"
  belongs_to :target_capture, class_name: "Capture"

  validates :relation_type, presence: true
  validates :target_capture_id, uniqueness: { scope: :source_capture_id }
  validate :cannot_link_capture_to_itself

  private

  def cannot_link_capture_to_itself
    return unless source_capture_id.present? && source_capture_id == target_capture_id

    errors.add(:target_capture_id, "cannot be the same as the source capture")
  end
end
