module Drive
  class BackfillRecordExports
    def initialize(user:)
      @user = user
    end

    def call
      return 0 unless user.google_drive_ready? && user.ensure_app_setting!.google_drive_backup?

      scheduled = 0

      pages_scope.find_each do |page|
        ScheduleRecordExport.new(record: page).call
        scheduled += 1
      end

      user.notepad_entries.find_each do |entry|
        ScheduleRecordExport.new(record: entry).call
        scheduled += 1
      end

      scheduled
    end

    private

    attr_reader :user

    def pages_scope
      Page.joins(chapter: :notebook).where(notebooks: { user_id: user.id })
    end
  end
end
