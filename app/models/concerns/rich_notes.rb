module RichNotes
  extend ActiveSupport::Concern

  included do
    before_validation :normalize_notes_html
  end

  def plain_notes
    html = notes.to_s
    return "" if html.blank?

    text = html.dup
    text.gsub!(%r{<br\s*/?>}i, "\n")
    text.gsub!(%r{<(li)\b[^>]*>}i, "- ")
    text.gsub!(%r{</(div|p|blockquote|h1|li|ul|ol|pre)>}i, "\n")

    Rails::Html::FullSanitizer.new
      .sanitize(text)
      .tr("\u00A0", " ")
      .gsub(/\r\n?/, "\n")
      .gsub(/[ \t]+\n/, "\n")
      .gsub(/\n{3,}/, "\n\n")
      .strip
  end

  private

  def normalize_notes_html
    self.notes = nil if plain_notes.blank?
  end
end
