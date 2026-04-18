module ScannedDocuments
  class ConfidenceEstimator
    def initialize(text:)
      @text = text.to_s
    end

    def call
      return nil if normalized_text.blank?
      return nil if compact_text.blank?

      score = 24.0
      score += [tokens.length, 20].min * 1.4
      score += [lines.length, 10].min * 1.6
      score += alphanumeric_ratio * 18.0
      score += clean_character_ratio * 12.0
      score += 8.0 if average_token_length.between?(3.0, 12.0)
      score += 6.0 if tokens.length >= 6
      score -= noisy_character_ratio * 35.0
      score -= repeated_symbol_runs * 4.0

      score.clamp(35.0, 96.0).round(1)
    end

    private

    attr_reader :text

    def normalized_text
      @normalized_text ||= text.gsub(/\r\n?/, "\n").strip
    end

    def compact_text
      @compact_text ||= normalized_text.gsub(/\s+/, "")
    end

    def tokens
      @tokens ||= normalized_text.scan(/[[:alnum:]][[:alnum:]&%'().,\/:-]*/)
    end

    def lines
      @lines ||= normalized_text.lines.map { |line| line.strip }.reject(&:blank?)
    end

    def alphanumeric_ratio
      @alphanumeric_ratio ||= compact_text.scan(/[[:alnum:]]/).length.to_f / compact_text.length
    end

    def clean_character_ratio
      @clean_character_ratio ||= compact_text.scan(/[[:alnum:]\.,:;!\?\-\/&%'()]/).length.to_f / compact_text.length
    end

    def noisy_character_ratio
      1.0 - clean_character_ratio
    end

    def average_token_length
      return 0.0 if tokens.empty?

      tokens.sum(&:length).to_f / tokens.length
    end

    def repeated_symbol_runs
      normalized_text.scan(/([^\p{Alnum}\s])\1+/).length
    end
  end
end
