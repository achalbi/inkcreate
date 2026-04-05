class AiSummary < ApplicationRecord
  belongs_to :capture

  validates :provider, presence: true

  scope :recent_first, -> { order(created_at: :desc) }
end
