module Captures
  class RequestOcr
    def initialize(capture:, request_id:)
      @capture = capture
      @request_id = request_id
    end

    def call
      ocr_job = capture.ocr_jobs.create!(
        status: :queued,
        provider: ENV.fetch("OCR_PROVIDER", "tesseract"),
        queued_at: Time.current,
        correlation_id: request_id
      )

      capture.update!(
        status: :queued,
        ocr_status: :processing
      )

      Async::Dispatcher.enqueue_ocr(ocr_job.id)
      ocr_job
    end

    private

    attr_reader :capture, :request_id
  end
end
