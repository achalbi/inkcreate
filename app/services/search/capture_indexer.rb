module Search
  class CaptureIndexer
    def initialize(capture:, ocr_result:)
      @capture = capture
      @ocr_result = ocr_result
    end

    def call
      capture.update!(
        search_text: [
          capture.title,
          capture.meeting_label,
          capture.conference_label,
          capture.project_label,
          ocr_result.cleaned_text
        ].compact.join("\n")
      )
    end

    private

    attr_reader :capture, :ocr_result
  end
end
