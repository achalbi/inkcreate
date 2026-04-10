class HomeController < BrowserController
  def show
    return render "landing/show" unless user_signed_in?

    @today = Time.zone.today
    @total_notebooks = current_user.notebooks.count
    @active_notebooks = current_user.notebooks.active.count
    @today_notepad_entries = current_user.notepad_entries.where(entry_date: @today).count
    @recent_notebooks = current_user.notebooks.includes(:chapters).ordered.limit(2)
    @recent_notepad_entries = current_user.notepad_entries.recent_first.limit(2)
    @reminders_available = Reminder.schema_ready?

    if @reminders_available
      upcoming_reminders = current_user.reminders.upcoming_first
      @new_reminder = current_user.reminders.new
      @upcoming_reminders_count = upcoming_reminders.count
      @upcoming_reminders = upcoming_reminders.limit(2)
    else
      @new_reminder = nil
      @upcoming_reminders_count = 0
      @upcoming_reminders = []
    end
  end
end
