require "test_helper"
require "digest/md5"

class ActiveStorage::BlobServiceMigratorTest < ActiveSupport::TestCase
  class FakeService
    attr_reader :uploads, :deleted_keys

    def initialize(objects = {})
      @objects = objects.transform_keys(&:to_s)
      @uploads = []
      @deleted_keys = []
    end

    def exist?(key)
      @objects.key?(key.to_s)
    end

    def open(key, checksum: nil)
      raise ActiveStorage::FileNotFoundError unless exist?(key)

      io = StringIO.new(@objects.fetch(key.to_s))
      io.binmode if io.respond_to?(:binmode)
      return io unless block_given?

      yield io
    ensure
      io&.close
    end

    def upload(key, io, checksum: nil, **options)
      io.rewind if io.respond_to?(:rewind)
      @objects[key.to_s] = io.read
      @uploads << { key: key.to_s, checksum: checksum, options: options }
    end

    def delete(key)
      @deleted_keys << key.to_s
      @objects.delete(key.to_s)
    end
  end

  test "copies blobs to the destination service and updates service_name" do
    blob = build_blob(service_name: "local", data: "page-bytes")
    source = FakeService.new(blob.key => "page-bytes")
    destination = FakeService.new

    result = ActiveStorage::BlobServiceMigrator.new(
      from_service: "local",
      to_service: "gcs",
      scope: ActiveStorage::Blob.where(id: blob.id),
      source_service: source,
      destination_service: destination,
      logger: Logger.new(nil)
    ).call

    assert_equal 1, result.scanned
    assert_equal 1, result.copy_candidates
    assert_equal 0, result.repoint_candidates
    assert_equal 0, result.missing
    assert_equal 0, result.failed
    assert_equal "gcs", blob.reload.service_name
    assert_equal 1, destination.uploads.size
    assert_equal blob.key, destination.uploads.first[:key]
  end

  test "repoints blobs when the destination already has the key" do
    blob = build_blob(service_name: "local", data: "page-bytes")
    source = FakeService.new(blob.key => "page-bytes")
    destination = FakeService.new(blob.key => "page-bytes")

    result = ActiveStorage::BlobServiceMigrator.new(
      from_service: "local",
      to_service: "gcs",
      scope: ActiveStorage::Blob.where(id: blob.id),
      source_service: source,
      destination_service: destination,
      logger: Logger.new(nil)
    ).call

    assert_equal 1, result.scanned
    assert_equal 0, result.copy_candidates
    assert_equal 1, result.repoint_candidates
    assert_equal 0, result.missing
    assert_equal 0, result.failed
    assert_equal "gcs", blob.reload.service_name
    assert_empty destination.uploads
  end

  test "reports blobs missing from the source service" do
    blob = build_blob(service_name: "local", data: "page-bytes")
    source = FakeService.new
    destination = FakeService.new

    result = ActiveStorage::BlobServiceMigrator.new(
      from_service: "local",
      to_service: "gcs",
      scope: ActiveStorage::Blob.where(id: blob.id),
      source_service: source,
      destination_service: destination,
      logger: Logger.new(nil)
    ).call

    assert_equal 1, result.scanned
    assert_equal 0, result.copy_candidates
    assert_equal 0, result.repoint_candidates
    assert_equal 1, result.missing
    assert_equal 0, result.failed
    assert_equal "local", blob.reload.service_name
  end

  test "supports a dry run without mutating blobs" do
    blob = build_blob(service_name: "local", data: "page-bytes")
    source = FakeService.new(blob.key => "page-bytes")
    destination = FakeService.new

    result = ActiveStorage::BlobServiceMigrator.new(
      from_service: "local",
      to_service: "gcs",
      scope: ActiveStorage::Blob.where(id: blob.id),
      source_service: source,
      destination_service: destination,
      dry_run: true,
      logger: Logger.new(nil)
    ).call

    assert_equal 1, result.scanned
    assert_equal 1, result.copy_candidates
    assert_equal 0, result.repoint_candidates
    assert_equal 0, result.missing
    assert_equal 0, result.failed
    assert_equal "local", blob.reload.service_name
    assert_empty destination.uploads
  end

  private

  def build_blob(service_name:, data:)
    ActiveStorage::Blob.create!(
      key: SecureRandom.base58(28),
      filename: "photo.jpg",
      content_type: "image/jpeg",
      metadata: {},
      byte_size: data.bytesize,
      checksum: Base64.strict_encode64(Digest::MD5.digest(data)),
      service_name: service_name
    )
  end
end
