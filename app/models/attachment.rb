class Attachment < ApplicationRecord
  TYPES = %w[image video audio file url youtube].freeze

  belongs_to :user
  belongs_to :capture
  has_one_attached :asset

  validates :attachment_type, presence: true, inclusion: { in: TYPES }
  validate :source_presence
  validate :url_required_for_external_links
  validate :asset_required_for_uploaded_media

  scope :recent_first, -> { order(created_at: :desc) }

  def stored_file?
    asset.attached?
  end

  def external_link?
    !stored_file?
  end

  def image?
    attachment_type == "image"
  end

  def video?
    attachment_type == "video"
  end

  def audio?
    attachment_type == "audio"
  end

  def display_title
    title.presence || asset.blob&.filename&.to_s || url.to_s
  end

  private

  def source_presence
    return if asset.attached? || url.present?

    errors.add(:base, "Provide a file upload or external URL.")
  end

  def url_required_for_external_links
    return unless %w[url youtube].include?(attachment_type)
    return if url.present?

    errors.add(:url, "can't be blank")
  end

  def asset_required_for_uploaded_media
    return unless %w[image video audio file].include?(attachment_type)
    return if asset.attached?

    errors.add(:asset, "must be attached")
  end
end
