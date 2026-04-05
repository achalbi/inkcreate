class PhysicalPage < ApplicationRecord
  TEMPLATE_TYPES = PageTemplate::SYSTEM_KEYS.freeze

  belongs_to :user

  has_many :captures, dependent: :nullify

  validates :page_number, presence: true, uniqueness: { scope: :user_id }
  validates :template_type, presence: true, inclusion: { in: TEMPLATE_TYPES }

  scope :active, -> { where(active: true).order(:page_number) }
end
