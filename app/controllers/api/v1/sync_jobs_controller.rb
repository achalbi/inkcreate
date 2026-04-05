module Api
  module V1
    class SyncJobsController < BaseController
      def index
        render json: {
          sync_jobs: current_user.sync_jobs.recent_first.as_json(
            only: %i[id syncable_type syncable_id job_type payload status attempts last_attempt_at error_message idempotency_key created_at updated_at]
          )
        }
      end

      def create
        sync_job = Sync::RecordJob.new(
          user: current_user,
          syncable: resolve_syncable,
          job_type: sync_job_params.fetch(:job_type),
          payload: sync_job_params.fetch(:payload, {}),
          idempotency_key: sync_job_params.fetch(:idempotency_key)
        ).call
        render json: { sync_job: sync_job.as_json }, status: :created
      end

      private

      def sync_job_params
        params.require(:sync_job).permit(:syncable_type, :syncable_id, :job_type, :idempotency_key, payload: {})
      end

      def resolve_syncable
        current_user.public_send(sync_job_params.fetch(:syncable_type).underscore.pluralize).find(sync_job_params.fetch(:syncable_id))
      end
    end
  end
end
