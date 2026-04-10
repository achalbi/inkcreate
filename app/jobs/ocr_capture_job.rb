class OcrCaptureJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  def perform(ocr_job_id)
    ocr_job = OcrJob.find(ocr_job_id)
    Current.request_id = ocr_job.correlation_id || job_id
    Current.user = ocr_job.capture.user

    Ocr::Pipeline.new(ocr_job: ocr_job).call
  ensure
    Current.reset
  end
end
