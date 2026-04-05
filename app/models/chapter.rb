class Chapter < ApplicationRecord
  belongs_to :notebook
  has_many :pages, -> { order(position: :asc, created_at: :asc) }, dependent: :destroy

  validates :title, presence: true
  validates :position, presence: true, numericality: { only_integer: true, greater_than: 0 }

  scope :ordered, -> { order(position: :asc, created_at: :asc) }

  before_validation :assign_position, on: :create

  delegate :user, to: :notebook

  private

  def assign_position
    self.position ||= (notebook&.chapters&.maximum(:position) || 0) + 1
  end
end
