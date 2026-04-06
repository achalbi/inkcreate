module Drive
  class RenameRecordFolder
    def initialize(record:)
      @record = record
      @user = record.user
      @google_drive_export = record.google_drive_export
    end

    def call
      return unless user.google_drive_ready?
      return unless google_drive_export&.remote_folder_id.present?

      drive_service.update_file(
        google_drive_export.remote_folder_id,
        Google::Apis::DriveV3::File.new(name: Drive::ExportLayout.record_folder_name(record)),
        fields: "id"
      )

      google_drive_export.update!(
        metadata: google_drive_export.metadata.to_h.merge(
          "folder_path" => Drive::ExportLayout.folder_segments(record),
          "folder_path_signature" => Drive::ExportLayout.folder_path_signature(record)
        )
      )
    rescue Google::Apis::ClientError
      nil
    end

    private

    attr_reader :record, :user, :google_drive_export

    def drive_service
      @drive_service ||= ClientFactory.build(user: user)
    end
  end
end
