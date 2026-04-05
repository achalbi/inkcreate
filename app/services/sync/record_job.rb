module Sync
  class RecordJob
    def initialize(user:, syncable:, job_type:, payload:, idempotency_key:)
      @user = user
      @syncable = syncable
      @job_type = job_type
      @payload = payload
      @idempotency_key = idempotency_key
    end

    def call
      user.sync_jobs.find_or_create_by!(idempotency_key: idempotency_key) do |sync_job|
        sync_job.syncable_type = syncable.class.name
        sync_job.syncable_id = syncable.id
        sync_job.job_type = job_type
        sync_job.payload = payload
        sync_job.status = :pending
      end
    end

    private

    attr_reader :user, :syncable, :job_type, :payload, :idempotency_key
  end
end
