class DailyLog < ApplicationRecord
  belongs_to :user

  has_many :captures, dependent: :nullify
  has_many :tasks, dependent: :nullify

  validates :entry_date, presence: true, uniqueness: { scope: :user_id }

  scope :recent_first, -> { order(entry_date: :desc) }

  def self.for_date!(user:, date:)
    find_by!(user:, entry_date: date)
  end

  def to_param
    entry_date.iso8601
  end

  def display_title
    title.presence || entry_date.strftime("%A, %b %-d")
  end
end
