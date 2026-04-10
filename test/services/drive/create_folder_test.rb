require "test_helper"

class DriveCreateFolderTest < ActiveSupport::TestCase
  Folder = Struct.new(:id, :name, keyword_init: true)
  EnsureFolderPathCall = Struct.new(:result, keyword_init: true) do
    def call
      result
    end
  end
  UserWithoutUsername = Struct.new(:id, :email, keyword_init: true)
  UserWithUsername = Struct.new(:id, :email, :username, keyword_init: true)

  test "uses the email local part and user id in the default root folder name" do
    user = UserWithoutUsername.new(id: "user-123", email: "alex.rivera@example.com")
    created_segments = []

    ensure_folder_path = lambda do |user:, segments:, parent_id: "root", **|
      created_segments << { user: user, parent_id: parent_id, segments: segments }
      EnsureFolderPathCall.new(result: Folder.new(id: "#{segments.first}-id", name: segments.first))
    end

    with_singleton_override(Drive::EnsureFolderPath, :new, ensure_folder_path) do
      folder = Drive::CreateFolder.new(user: user).call

      assert_equal "inkcreate-alex-rivera-user-123", folder.name
      assert_equal [
        { user: user, parent_id: "root", segments: ["inkcreate-alex-rivera-user-123"] },
        { user: user, parent_id: "inkcreate-alex-rivera-user-123-id", segments: ["Notebooks"] },
        { user: user, parent_id: "inkcreate-alex-rivera-user-123-id", segments: ["Notepad"] }
      ], created_segments
    end
  end

  test "prefers username when the user responds to it" do
    user = UserWithUsername.new(
      id: "9f3b0f83-3c77-4ad9-b6bd-2f671fe4a2aa",
      email: "fallback@example.com",
      username: "Asha Notes"
    )
    created_segments = []

    ensure_folder_path = lambda do |user:, segments:, parent_id: "root", **|
      created_segments << { user: user, parent_id: parent_id, segments: segments }
      EnsureFolderPathCall.new(result: Folder.new(id: "#{segments.first}-id", name: segments.first))
    end

    with_singleton_override(Drive::EnsureFolderPath, :new, ensure_folder_path) do
      folder = Drive::CreateFolder.new(user: user).call

      assert_equal "inkcreate-asha-notes-9f3b0f83-3c77-4ad9-b6bd-2f671fe4a2aa", folder.name
      assert_equal "inkcreate-asha-notes-9f3b0f83-3c77-4ad9-b6bd-2f671fe4a2aa", created_segments.first[:segments].first
    end
  end

  private

  def with_singleton_override(target, method_name, implementation)
    eigenclass = class << target; self; end
    backup_method = :"__codex_backup_#{method_name}_#{Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)}"
    had_original = eigenclass.method_defined?(method_name) || eigenclass.private_method_defined?(method_name)

    eigenclass.alias_method backup_method, method_name if had_original
    eigenclass.define_method(method_name, implementation)

    yield
  ensure
    eigenclass.remove_method(method_name) if eigenclass.method_defined?(method_name) || eigenclass.private_method_defined?(method_name)

    if had_original
      eigenclass.alias_method method_name, backup_method
      eigenclass.remove_method(backup_method)
    end
  end
end
