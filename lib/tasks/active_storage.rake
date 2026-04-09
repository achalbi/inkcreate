namespace :active_storage do
  desc "Migrate Active Storage blobs between configured services with FROM_SERVICE=local TO_SERVICE=gcs [DRY_RUN=true] [PURGE_SOURCE=true]"
  task migrate_service: :environment do
    boolean = ActiveModel::Type::Boolean.new
    from_service = ENV.fetch("FROM_SERVICE")
    to_service = ENV.fetch("TO_SERVICE")
    dry_run = boolean.cast(ENV.fetch("DRY_RUN", false))
    purge_source = boolean.cast(ENV.fetch("PURGE_SOURCE", false))

    result = ActiveStorage::BlobServiceMigrator.new(
      from_service: from_service,
      to_service: to_service,
      dry_run: dry_run,
      purge_source: purge_source
    ).call

    prefix = dry_run ? "Dry run complete" : "Migration complete"
    copy_label = dry_run ? "would_copy" : "copied"
    repoint_label = dry_run ? "would_repoint" : "repointed"

    puts [
      prefix,
      "scanned=#{result.scanned}",
      "#{copy_label}=#{result.copy_candidates}",
      "#{repoint_label}=#{result.repoint_candidates}",
      "missing=#{result.missing}",
      "failed=#{result.failed}"
    ].join(" ")

    abort "Migration finished with unresolved missing or failed blobs." if result.missing.positive? || result.failed.positive?
  end
end
