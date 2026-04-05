class Project < ApplicationRecord
  belongs_to :user

  has_many :captures, dependent: :nullify
  has_many :tasks, dependent: :nullify

  validates :title, presence: true
  validates :slug, presence: true, uniqueness: { scope: :user_id }

  before_validation :assign_slug

  scope :active, -> { where(archived_at: nil) }
  scope :recent_first, -> { order(updated_at: :desc, created_at: :desc) }

  def archived?
    archived_at.present?
  end

  private

  def assign_slug
    self.slug = title.to_s.parameterize if slug.blank? && title.present?
  end
end
