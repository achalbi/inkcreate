module Captures
  class PreviewUrl
    def initialize(capture:)
      @capture = capture
    end

    def call
      storage.bucket(capture.storage_bucket, skip_lookup: true).signed_url(
        capture.storage_object_key,
        method: "GET",
        expires: 10.minutes.from_now,
        response: {
          "content_type" => capture.content_type,
          "content_disposition" => "inline; filename=\"#{capture.original_filename}\""
        }
      )
    end

    private

    attr_reader :capture

    def storage
      @storage ||= Google::Cloud::Storage.new(project_id: ENV.fetch("GCP_PROJECT_ID"))
    end
  end
end
