module RetainsPendingPhotos
  extend ActiveSupport::Concern

  included do
    attr_writer :retained_photo_signed_ids
  end

  def retained_photo_signed_ids
    Array(@retained_photo_signed_ids).reject(&:blank?)
  end

  def pending_photo_blobs
    retained_photo_signed_ids.filter_map do |signed_id|
      ActiveStorage::Blob.find_signed(signed_id)
    end
  end
end
