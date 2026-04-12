module Internal
  class RemindersController < BaseController
    def perform
      DispatchDueRemindersJob.perform_now(params[:id])
      head :accepted
    end
  end
end
