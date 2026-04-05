class Notebook < ApplicationRecord
  attribute :status, :integer, default: 0

  belongs_to :user

  has_many :all_chapters, -> { order(position: :asc, created_at: :asc) }, class_name: "Chapter", dependent: :destroy, inverse_of: :notebook
  has_many :chapters, -> { kept.ordered }, class_name: "Chapter", inverse_of: :notebook
  has_many :deleted_chapters, -> { deleted.ordered }, class_name: "Chapter", inverse_of: :notebook
  has_many :pages, through: :chapters
  has_many :captures, dependent: :nullify

  enum :status, { active: 0, archived: 1 }, prefix: true

  validates :title, presence: true
  validates :status, presence: true
  validates :slug, presence: true, uniqueness: { scope: :user_id }

  scope :active, -> { where(status: statuses[:active]) }
  scope :archived, -> { where(status: statuses[:archived]) }
  scope :ordered, -> { order(updated_at: :desc, created_at: :desc) }

  before_validation :sync_legacy_fields

  private

  def sync_legacy_fields
    self.title = name if name.present? && (title.blank? || will_save_change_to_name?)
    self.name = title if has_attribute?(:name) && title.present? && (name.blank? || will_save_change_to_title?)
    self.status = archived_at.present? ? :archived : :active if status.nil?
    self.archived_at = status_archived? ? (archived_at || Time.current) : nil
    self.slug = title.to_s.parameterize if slug.blank? && title.present?
  end
end
