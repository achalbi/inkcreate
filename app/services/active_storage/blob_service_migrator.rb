module ActiveStorage
  class BlobServiceMigrator
    Result = Struct.new(
      :scanned,
      :copy_candidates,
      :repoint_candidates,
      :missing,
      :failed,
      keyword_init: true
    )

    def initialize(from_service:, to_service:, scope: ActiveStorage::Blob.all, source_service: nil, destination_service: nil, dry_run: false, purge_source: false, logger: Rails.logger)
      @from_service = from_service.to_s
      @to_service = to_service.to_s
      @scope = scope
      @source_service = source_service
      @destination_service = destination_service
      @dry_run = dry_run
      @purge_source = purge_source
      @logger = logger
    end

    def call
      raise ArgumentError, "Source and destination services must be different" if from_service == to_service

      result = Result.new(scanned: 0, copy_candidates: 0, repoint_candidates: 0, missing: 0, failed: 0)

      blobs_to_migrate.find_each do |blob|
        result.scanned += 1

        if destination_service.exist?(blob.key)
          result.repoint_candidates += 1
          repoint_blob!(blob)
          next
        end

        unless source_service.exist?(blob.key)
          result.missing += 1
          logger.error("Active Storage blob #{blob.id} is missing from #{from_service} (key=#{blob.key})")
          next
        end

        result.copy_candidates += 1
        copy_blob!(blob)
      rescue StandardError => error
        result.failed += 1
        logger.error("Active Storage blob #{blob.id} failed to migrate from #{from_service} to #{to_service}: #{error.class}: #{error.message}")
      end

      result
    end

    private

    attr_reader :from_service, :to_service, :scope, :source_service, :destination_service, :logger

    def dry_run?
      @dry_run
    end

    def purge_source?
      @purge_source
    end

    def blobs_to_migrate
      scope.where(service_name: from_service)
    end

    def source_service
      @source_service ||= ActiveStorage::Blob.services.fetch(from_service)
    end

    def destination_service
      @destination_service ||= ActiveStorage::Blob.services.fetch(to_service)
    end

    def repoint_blob!(blob)
      if dry_run?
        logger.info("Would repoint Active Storage blob #{blob.id} to #{to_service} because key #{blob.key} already exists there")
        return
      end

      blob.update_columns(service_name: to_service)
      delete_source_blob(blob) if purge_source?
      logger.info("Repointed Active Storage blob #{blob.id} to #{to_service}")
    end

    def copy_blob!(blob)
      if dry_run?
        logger.info("Would copy Active Storage blob #{blob.id} from #{from_service} to #{to_service}")
        return
      end

      source_service.open(blob.key, checksum: blob.checksum) do |file|
        file.binmode if file.respond_to?(:binmode)

        destination_service.upload(
          blob.key,
          file,
          checksum: blob.checksum,
          content_type: blob.content_type,
          filename: blob.filename,
          custom_metadata: blob.custom_metadata
        )
      end

      blob.update_columns(service_name: to_service)
      delete_source_blob(blob) if purge_source?
      logger.info("Copied Active Storage blob #{blob.id} from #{from_service} to #{to_service}")
    end

    def delete_source_blob(blob)
      return unless source_service.exist?(blob.key)

      source_service.delete(blob.key)
      logger.info("Deleted source object for Active Storage blob #{blob.id} from #{from_service}")
    end
  end
end
