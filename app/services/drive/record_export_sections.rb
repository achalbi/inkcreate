module Drive
  module RecordExportSections
    RECORD = "record".freeze
    TODO = "todo".freeze
    PHOTOS = "photos".freeze
    VOICE_NOTES = "voice_notes".freeze
    SCANNED_DOCUMENTS = "scanned_documents".freeze
    ALL = [
      RECORD,
      TODO,
      PHOTOS,
      VOICE_NOTES,
      SCANNED_DOCUMENTS
    ].freeze
    NOTES_DEPENDENT = [RECORD, TODO, VOICE_NOTES, SCANNED_DOCUMENTS].freeze
    PENDING_METADATA_KEY = "pending_sections".freeze

    def self.normalize(sections)
      values = Array(sections).flatten.compact.map { |section| section.to_s }.reject(&:blank?)
      return ALL if values.blank? || values.include?("all")

      values.select { |section| ALL.include?(section) }.uniq
    end

    def self.remaining(current:, processed:)
      normalize(current) - normalize(processed)
    end

    def self.notes_required?(sections)
      (normalize(sections) & NOTES_DEPENDENT).any?
    end

    def self.manifest_required?(sections)
      normalize(sections).any?
    end

    def self.photos_required?(sections)
      normalize(sections).include?(PHOTOS)
    end

    def self.voice_notes_required?(sections)
      normalize(sections).include?(VOICE_NOTES)
    end

    def self.scanned_documents_required?(sections)
      normalize(sections).include?(SCANNED_DOCUMENTS)
    end
  end
end
