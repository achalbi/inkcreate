module Drive
  class CreateFolder
    DEFAULT_FOLDER_NAME = "Inkcreate".freeze
    DEFAULT_CHILD_FOLDERS = ["Notebooks", "Notepad"].freeze

    def initialize(user:, name: DEFAULT_FOLDER_NAME)
      @user = user
      @name = name
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
  end
end
