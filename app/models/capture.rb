class Capture < ApplicationRecord
  CONTENT_TYPES = %w[
    image/heic
    image/heif
    image/jpeg
    image/png
    image/webp
  ].freeze

  enum :status, {
    uploaded: 0,
    queued: 10,
    processing: 20,
    ready: 30,
    failed: 40
  }, prefix: true

  enum :drive_sync_mode, {
    manual: 0,
    automatic: 10
  }, prefix: true

  enum :ocr_status, {
    not_started: 0,
    processing: 1,
    completed: 2,
    failed: 3
  }, prefix: true

  enum :ai_status, {
    not_started: 0,
    processing: 1,
    completed: 2,
    failed: 3
  }, prefix: true

  enum :backup_status, {
    local_only: 0,
    pending: 1,
    uploaded: 2,
    failed: 3
  }, prefix: true

  enum :sync_status, {
    local_only: 0,
    pending: 1,
    synced: 2,
    conflict: 3,
    failed: 4
  }, prefix: true

  belongs_to :user
  belongs_to :notebook, optional: true
  belongs_to :page_template, optional: true
  belongs_to :project, optional: true
  belongs_to :daily_log, optional: true
  belongs_to :physical_page, optional: true

  has_many :ocr_jobs, dependent: :destroy
  has_many :ocr_results, dependent: :destroy
  has_many :drive_syncs, dependent: :destroy
  has_many :capture_tags, dependent: :destroy
  has_many :tags, through: :capture_tags
  has_many :capture_revisions, dependent: :destroy
  has_many :attachments, dependent: :destroy
  has_many :ai_summaries, dependent: :destroy
  has_many :tasks, dependent: :nullify
  has_many :backup_records, dependent: :destroy
  has_many :outgoing_reference_links, class_name: "ReferenceLink", foreign_key: :source_capture_id, dependent: :destroy
  has_many :incoming_reference_links, class_name: "ReferenceLink", foreign_key: :target_capture_id, dependent: :destroy
  has_many :related_captures, through: :outgoing_reference_links, source: :target_capture

  validates :original_filename, :content_type, :storage_bucket, :storage_object_key, presence: true
  validates :content_type, inclusion: { in: CONTENT_TYPES }
  validates :byte_size, numericality: { greater_than: 0, less_than_or_equal_to: 25.megabytes }
  validates :page_type, presence: true, allow_blank: false

  scope :recent_first, -> { order(captured_at: :desc, created_at: :desc) }
  scope :active, -> { where(archived_at: nil) }
  scope :favorited, -> { where(favorite: true) }
  scope :inbox, -> { where(project_id: nil, daily_log_id: nil, archived_at: nil) }

  def latest_ocr_result
    ocr_results.order(created_at: :desc).first
  end

  def latest_ai_summary
    ai_summaries.order(created_at: :desc).first
  end

  def display_title
    title.presence || original_filename
  end

  def archived?
    archived_at.present?
  end
end
