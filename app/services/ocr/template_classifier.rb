module Ocr
  class TemplateClassifier
    Result = Struct.new(:page_template, :confidence, keyword_init: true)

    def initialize(capture:, cleaned_text:)
      @capture = capture
      @cleaned_text = cleaned_text.to_s
    end

    def call
      return Result.new(page_template: capture.page_template, confidence: 1.0) if capture.page_template.present?

      if cleaned_text.match?(/\[[ xX]\]|☐|☑/)
        Result.new(page_template: template_for("checklist"), confidence: 0.82)
      elsif cleaned_text.match?(/priority/i) && cleaned_text.match?(/severity/i)
        Result.new(page_template: template_for("priority_severity"), confidence: 0.86)
      elsif cleaned_text.lines.count { |line| line.match?(/\S/) } >= 6
        Result.new(page_template: template_for("single_line"), confidence: 0.42)
      else
        Result.new(page_template: template_for("blank"), confidence: 0.2)
      end
    end

    private

    attr_reader :capture, :cleaned_text

    def template_for(key)
      PageTemplate.find_by!(key: key)
    end
  end
end
