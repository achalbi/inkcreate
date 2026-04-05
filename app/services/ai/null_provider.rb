module Ai
  class NullProvider
    def summarize_capture(capture)
      source_text = capture.latest_ocr_result&.cleaned_text.presence || capture.description.to_s
      lines = source_text.split(/\n+/).map(&:squish).reject(&:blank?)
      bullets = lines.first(5)

      ProviderResult.new(
        summary: if bullets.any?
          "Summary generated from the current OCR or note text. Edit it freely."
        else
          "No OCR text is available yet. Add a description or run text extraction first."
        end,
        bullets: bullets,
        tasks: extract_tasks(lines),
        entities: [],
        raw_payload: { provider: "null", generated_at: Time.current.iso8601 }
      )
    end

    private

    def extract_tasks(lines)
      lines.grep(/\b(todo|follow up|next|action|deadline)\b/i).first(5).map do |line|
        { title: line.delete_prefix("-").strip }
      end
    end
  end
end
