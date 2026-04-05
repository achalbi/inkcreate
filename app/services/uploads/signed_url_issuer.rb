module Uploads
  class SignedUrlIssuer
    Result = Struct.new(:signed_url, :bucket, :object_key, :expires_at, :headers, keyword_init: true) do
      def as_json(*)
        {
          signed_url: signed_url,
          bucket: bucket,
          object_key: object_key,
          expires_at: expires_at,
          headers: headers
        }
      end
    end

    ALLOWED_CONTENT_TYPES = Capture::CONTENT_TYPES.freeze
    MAX_UPLOAD_BYTES = 25.megabytes

    def initialize(user:, filename:, content_type:, byte_size:)
      @user = user
      @filename = filename
      @content_type = content_type
      @byte_size = byte_size.to_i
    end

    def call
      validate!

      object_key = ObjectKeyBuilder.call(user_id: user.id, filename: filename)
      expires_at = 10.minutes.from_now
      bucket_name = ENV.fetch("GCS_UPLOAD_BUCKET")
      bucket = storage.bucket(bucket_name, skip_lookup: true)

      signed_url = bucket.signed_url(
        object_key,
        method: "PUT",
        expires: expires_at,
        content_type: content_type
      )

      Result.new(
        signed_url: signed_url,
        bucket: bucket_name,
        object_key: object_key,
        expires_at: expires_at.iso8601,
        headers: { "Content-Type" => content_type }
      )
    end

    private

    attr_reader :user, :filename, :content_type, :byte_size

    def validate!
      raise ArgumentError, "Unsupported content type" unless ALLOWED_CONTENT_TYPES.include?(content_type)
      raise ArgumentError, "Upload too large" if byte_size <= 0 || byte_size > MAX_UPLOAD_BYTES
      raise ArgumentError, "Filename is required" if filename.blank?
    end

    def storage
      @storage ||= Google::Cloud::Storage.new(project_id: ENV.fetch("GCP_PROJECT_ID"))
    end
  end
end
