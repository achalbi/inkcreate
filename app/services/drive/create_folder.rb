module Drive
  class CreateFolder
    DEFAULT_FOLDER_PREFIX = "inkcreate".freeze
    DEFAULT_CHILD_FOLDERS = ["Notebooks", "Notepad"].freeze

    def initialize(user:, name: nil)
      @user = user
      @name = name.presence || default_folder_name
    end

    def call
      root_folder = Drive::EnsureFolderPath.new(user: user, segments: [name]).call
      DEFAULT_CHILD_FOLDERS.each do |child_folder|
        Drive::EnsureFolderPath.new(user: user, parent_id: root_folder.id, segments: [child_folder]).call
      end
      root_folder
    end

    private

    attr_reader :user, :name

    def default_folder_name
      [DEFAULT_FOLDER_PREFIX, normalized_username, user.id].join("-")
    end

    def normalized_username
      username =
        if user.respond_to?(:username) && user.username.present?
          user.username
        else
          user.email.to_s.split("@").first
        end

      username.to_s.parameterize(separator: "-").presence || "user"
    end
  end
end
