class Tag < ApplicationRecord
  belongs_to :user

  has_many :capture_tags, dependent: :destroy
  has_many :captures, through: :capture_tags

  validates :name, presence: true, uniqueness: { scope: :user_id, case_sensitive: false }

  before_validation :normalize_name

  private

  def normalize_name
    self.name = name.to_s.squish
  end
end
