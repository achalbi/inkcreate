module Drive
  class EnsureFolderPath
    FOLDER_MIME_TYPE = "application/vnd.google-apps.folder".freeze

    def initialize(user:, parent_id: "root", segments:, create_missing: true)
      @user = user
      @parent_id = parent_id
      @segments = Array(segments).filter_map { |segment| sanitize(segment) }
      @create_missing = create_missing
    end

    def call
      current_parent_id = parent_id
      last_folder = nil

      segments.each do |segment|
        last_folder = find_folder(parent_id: current_parent_id, name: segment)
        return if last_folder.nil? && !create_missing

        last_folder ||= create_folder(parent_id: current_parent_id, name: segment)
        current_parent_id = last_folder.id
      end

      last_folder
    rescue Google::Apis::AuthorizationError, Google::Auth::AuthorizationError, Signet::AuthorizationError
      raise Drive::ClientFactory::AuthorizationRequiredError, "Google Drive authorization expired. Reconnect Google Drive and try again."
    end

    private

    attr_reader :user, :parent_id, :segments, :create_missing

    def drive_service
      @drive_service ||= ClientFactory.build(user: user)
    end

    def find_folder(parent_id:, name:)
      response = drive_service.list_files(
        q: folder_query(parent_id: parent_id, name: name),
        fields: "files(id,name,webViewLink)",
        page_size: 1
      )

      response.files.first
    end

    def create_folder(parent_id:, name:)
      drive_service.create_file(
        Google::Apis::DriveV3::File.new(
          name: name,
          mime_type: FOLDER_MIME_TYPE,
          parents: [parent_id]
        ),
        fields: "id,name,webViewLink"
      )
    end

    def folder_query(parent_id:, name:)
      escaped_name = name.gsub("\\", "\\\\\\").gsub("'", "\\\\'")
      "'#{parent_id}' in parents and mimeType = '#{FOLDER_MIME_TYPE}' and trashed = false and name = '#{escaped_name}'"
    end

    def sanitize(segment)
      value = segment.to_s.squish
      return if value.blank?

      value.tr("/\\\\", "-").truncate(120, omission: "").strip.presence
    end
  end
end
