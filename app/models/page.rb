class Page < ApplicationRecord
  belongs_to :chapter
  has_many_attached :photos

  # Titles stay required because pages appear in nested notebook lists,
  # and a visible label keeps the hierarchy scannable on mobile.
  validates :title, presence: true
  validates :position, presence: true, numericality: { only_integer: true, greater_than: 0 }

  scope :ordered, -> { order(position: :asc, created_at: :asc) }

  before_validation :assign_position, on: :create

  delegate :notebook, to: :chapter
  delegate :user, to: :notebook

  private

  def assign_position
    self.position ||= (chapter&.pages&.maximum(:position) || 0) + 1
  end
end
