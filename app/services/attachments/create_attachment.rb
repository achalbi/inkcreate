module Attachments
  class CreateAttachment
    def initialize(user:, capture:, params:)
      @user = user
      @capture = capture
      @params = params
    end

    def call
      attachment = capture.attachments.new(
        user: user,
        attachment_type: resolved_attachment_type,
        title: params[:title].presence,
        url: resolved_url,
        metadata: params[:metadata] || {}
      )

      attach_uploaded_file!(attachment)
      hydrate_blob_metadata!(attachment)
      attachment.save!
      attachment
    end

    private

    attr_reader :user, :capture, :params

    def uploaded_file
      params[:file] || params[:asset]
    end

    def resolved_url
      return nil if uploaded_file.present?

      params[:url].presence
    end

    def resolved_attachment_type
      requested_type = params[:attachment_type].presence

      if uploaded_file.present?
        return requested_type if %w[image video audio file].include?(requested_type)

        return infer_uploaded_type
      end

      return requested_type if %w[url youtube].include?(requested_type)

      inferred_attachment_type
    end

    def inferred_attachment_type
      return infer_uploaded_type if uploaded_file.present?
      return "youtube" if youtube_url?

      "url"
    end

    def youtube_url?
      url = params[:url].to_s
      url.include?("youtube.com") || url.include?("youtu.be")
    end

    def infer_uploaded_type
      content_type = uploaded_file.content_type.to_s

      return "image" if content_type.start_with?("image/")
      return "video" if content_type.start_with?("video/")
      return "audio" if content_type.start_with?("audio/")

      "file"
    end

    def attach_uploaded_file!(attachment)
      return unless uploaded_file.present?

      attachment.asset.attach(uploaded_file)
    end

    def hydrate_blob_metadata!(attachment)
      return unless attachment.asset.attached?

      attachment.storage_key = attachment.asset.blob.key
      attachment.content_type = attachment.asset.blob.content_type
      attachment.byte_size = attachment.asset.blob.byte_size
    end
  end
end
