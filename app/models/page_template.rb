class PageTemplate < ApplicationRecord
  SYSTEM_KEYS = %w[
    blank
    single_line
    checkered
    todo
    checklist
    priority_severity
  ].freeze

  has_many :captures, dependent: :nullify

  validates :key, presence: true, inclusion: { in: SYSTEM_KEYS }, uniqueness: true
  validates :name, presence: true

  def template_type
    key
  end
end
