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
      return true if export.exported_at.blank?

      record.updated_at.present? && export.exported_at < record.updated_at
    end
  end
end
