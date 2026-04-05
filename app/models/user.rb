class User < ApplicationRecord
  devise :database_authenticatable, :registerable, :recoverable, :rememberable, :validatable

  enum :role, { user: 0, admin: 1 }

  encrypts :google_drive_access_token
  encrypts :google_drive_refresh_token

  has_many :notebooks, dependent: :destroy
  has_many :notepad_entries, dependent: :destroy
  has_many :projects, dependent: :destroy
  has_many :daily_logs, dependent: :destroy
  has_many :physical_pages, dependent: :destroy
  has_many :captures, dependent: :destroy
  has_many :tags, dependent: :destroy
  has_many :attachments, dependent: :destroy
  has_many :tasks, dependent: :destroy
  has_many :reference_links, dependent: :destroy
  has_many :backup_records, dependent: :destroy
  has_many :sync_jobs, dependent: :destroy
  has_many :drive_syncs, dependent: :destroy
  has_one :app_setting, dependent: :destroy

  before_validation :assign_bootstrap_role, on: :create
  after_create :ensure_app_setting!

  validates :time_zone, presence: true
  validates :locale, presence: true
  validates :role, presence: true

  def ensure_app_setting!
    app_setting || create_app_setting!
  end

  def role=(value)
    @role_explicitly_assigned = true unless value.nil?
    super
  end

  def google_drive_connected?
    google_drive_connected_at.present? && google_drive_refresh_token.present?
  end

  private

  def assign_bootstrap_role
    return if @role_explicitly_assigned

    self.role = self.class.unscoped.exists? ? :user : :admin
  end
end
