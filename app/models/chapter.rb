class Chapter < ApplicationRecord
  belongs_to :notebook
  has_many :pages, -> { order(position: :asc, created_at: :asc) }, dependent: :destroy

  validates :title, presence: true
  validates :position, presence: true, numericality: { only_integer: true, greater_than: 0 }

  scope :kept, -> { where(deleted_at: nil) }
  scope :deleted, -> { where.not(deleted_at: nil) }
  scope :ordered, -> { order(position: :asc, created_at: :asc) }

  before_validation :assign_position, on: :create

  delegate :user, to: :notebook

  def soft_deleted?
    deleted_at.present?
  end

  def soft_delete!
    update!(deleted_at: deleted_at || Time.current)
  end

  def restore!
    update!(deleted_at: nil)
  end

  private

  def assign_position
    self.position ||= (notebook&.all_chapters&.maximum(:position) || 0) + 1
  end
end
