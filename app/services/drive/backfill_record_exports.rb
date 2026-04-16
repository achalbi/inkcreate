module Drive
  class BackfillRecordExports
    def initialize(user:)
      @user = user
    end

    def call
      return 0 unless user.google_drive_ready? && user.ensure_app_setting!.google_drive_backup?

      scheduled = 0

      pages_scope.find_each do |page|
        scheduled += 1 if needs_export?(page) && ScheduleRecordExport.new(record: page).call.present?
      end

      user.notepad_entries.find_each do |entry|
        scheduled += 1 if needs_export?(entry) && ScheduleRecordExport.new(record: entry).call.present?
      end

      scheduled
    end

    private

    attr_reader :user

    def pages_scope
      Page.joins(chapter: :notebook).where(notebooks: { user_id: user.id })
    end

    def needs_export?(record)
      export = GoogleDriveExport.find_by(exportable: record)
      return true if export.blank?
      return true if export.status_failed?
      return true if export.metadata.to_h[Drive::RecordExportSections::PENDING_METADATA_KEY].present?
      return true if export.exported_at.blank?

      export.exported_at < record_last_change_at(record)
    end

    def record_last_change_at(record)
      [
        record.updated_at,
        photo_change_at(record),
        voice_note_change_at(record),
        scanned_document_change_at(record),
        todo_change_at(record)
      ].compact.max || record.updated_at || Time.at(0)
    end

    def photo_change_at(record)
      return unless record.respond_to?(:photos)

      record.photos.attachments.maximum(:created_at)
    end

    def voice_note_change_at(record)
      return unless record.respond_to?(:voice_notes)

      record.voice_notes.maximum(:updated_at)
    end

    def scanned_document_change_at(record)
      return unless record.respond_to?(:scanned_documents)

      record.scanned_documents.maximum(:updated_at)
    end

    def todo_change_at(record)
      return unless record.respond_to?(:todo_list)

      todo_list = record.todo_list
      return if todo_list.blank?

      [
        todo_list.updated_at,
        todo_list.todo_items.maximum(:updated_at),
        reminder_change_at(todo_list)
      ].compact.max
    end

    def reminder_change_at(todo_list)
      reminder_scope = Reminder.where(
        target_type: "TodoItem",
        target_id: todo_list.todo_items.select(:id)
      )
      reminder_scope.maximum(:updated_at)
    end
  end
end
