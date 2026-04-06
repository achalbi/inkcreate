module Drive
  class RenameNotebookFolder
    def initialize(notebook:, previous_title:)
      @notebook = notebook
      @previous_title = previous_title.to_s
      @user = notebook.user
    end

    def call
      return if previous_title.blank? || previous_title == notebook.title
      return unless user.google_drive_ready?

      folder = Drive::EnsureFolderPath.new(
        user: user,
        parent_id: user.google_drive_folder_id,
        segments: [
          "Notebooks",
          Drive::ExportLayout.titled_segment(previous_title, notebook.id)
        ],
        create_missing: false
      ).call

      return unless folder

      drive_service.update_file(
        folder.id,
        Google::Apis::DriveV3::File.new(name: Drive::ExportLayout.notebook_segment(notebook)),
        fields: "id"
      )

      refresh_page_export_metadata!
    rescue Google::Apis::ClientError
      nil
    end

    private

    attr_reader :notebook, :previous_title, :user

    def drive_service
      @drive_service ||= ClientFactory.build(user: user)
    end

    def refresh_page_export_metadata!
      notebook.pages.includes(:google_drive_export, chapter: :notebook).find_each do |page|
        next unless page.google_drive_export

        page.google_drive_export.update!(
          metadata: page.google_drive_export.metadata.to_h.merge(
            "folder_path" => Drive::ExportLayout.folder_segments(page),
            "folder_path_signature" => Drive::ExportLayout.folder_path_signature(page)
          )
        )
      end
    end
  end
end
