module Uploads
  class ObjectKeyBuilder
    def self.call(user_id:, filename:)
      extension = File.extname(filename.to_s).downcase.presence || ".jpg"
      date_path = Time.current.utc.strftime("%Y/%m/%d")

      "users/#{user_id}/uploads/#{date_path}/#{SecureRandom.uuid}#{extension}"
    end
  end
end
