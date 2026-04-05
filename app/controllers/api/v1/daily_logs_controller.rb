module Api
  module V1
    class DailyLogsController < BaseController
      def index
        render json: {
          daily_logs: current_user.daily_logs.recent_first.as_json(
            only: %i[id entry_date title summary quick_note created_at updated_at]
          )
        }
      end

      def show
        daily_log = current_user.daily_logs.find(params[:id])
        render json: { daily_log: daily_log.as_json(only: %i[id entry_date title summary quick_note created_at updated_at]) }
      end

      def create
        daily_log = current_user.daily_logs.find_or_create_by!(entry_date: daily_log_params.fetch(:entry_date)) do |record|
          record.title = daily_log_params[:title]
          record.summary = daily_log_params[:summary]
          record.quick_note = daily_log_params[:quick_note]
        end
        render json: { daily_log: daily_log.as_json(only: %i[id entry_date title summary quick_note created_at updated_at]) }, status: :created
      end

      private

      def daily_log_params
        params.require(:daily_log).permit(:entry_date, :title, :summary, :quick_note)
      end
    end
  end
end
