class CaptureStudioController < BrowserController
  before_action :require_authenticated_user!

  def show
    @entry_date = Time.zone.today
    @notepad_entry = current_user.notepad_entries.new(entry_date: @entry_date)
  end
end
