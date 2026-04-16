require "test_helper"

class MigrationVersionsTest < ActiveSupport::TestCase
  test "migration versions are unique" do
    versions = Dir[Rails.root.join("db/migrate/*.rb")]
      .map { |path| File.basename(path).split("_", 2).first }

    duplicates = versions
      .group_by(&:itself)
      .select { |_version, entries| entries.size > 1 }
      .keys

    assert_empty duplicates, "Duplicate migration versions found: #{duplicates.join(", ")}"
  end
end
