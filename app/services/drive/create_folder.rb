module Drive
  class CreateFolder
    DEFAULT_FOLDER_NAME = "Inkcreate Backups".freeze

    def initialize(user:, name: DEFAULT_FOLDER_NAME)
      @user = user
      @name = name
    end

    def call
      ClientFactory.build(user: user).create_file(
        Google::Apis::DriveV3::File.new(
          name: name,
          mime_type: "application/vnd.google-apps.folder"
        ),
        fields: "id,name,webViewLink"
      )
    end

    private

    attr_reader :user, :name
  end
end
