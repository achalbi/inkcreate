module Internal
  class OcrJobsController < BaseController
    def perform
      ocr_job = OcrJob.find(params[:id])
      Current.user = ocr_job.capture.user
      Ocr::Pipeline.new(ocr_job: ocr_job).call
      head :accepted
    ensure
      Current.reset
    end
  end
end
