module Uploads
  class ObjectVerifier
    MAX_UPLOAD_BYTES = 25.megabytes

    def initialize(bucket:, object_key:, user_id:)
      @bucket = bucket
      @object_key = object_key
      @user_id = user_id
    end

    def call
      raise ArgumentError, "Object key does not belong to the current user" unless object_key.start_with?("users/#{user_id}/")

      file = storage.bucket(bucket).file(object_key)
      raise ArgumentError, "Uploaded object not found" unless file
      raise ArgumentError, "Uploaded file is empty" if file.size.to_i <= 0
      raise ArgumentError, "Uploaded file exceeds allowed size" if file.size.to_i > MAX_UPLOAD_BYTES
      raise ArgumentError, "Unsupported content type" unless Capture::CONTENT_TYPES.include?(file.content_type)

      file
    end

    private

    attr_reader :bucket, :object_key, :user_id

    def storage
      @storage ||= Google::Cloud::Storage.new(project_id: ENV.fetch("GCP_PROJECT_ID"))
    end
  end
end
