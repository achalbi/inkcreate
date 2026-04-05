class HomeController < BrowserController
  def show
    return render "landing/show" unless user_signed_in?

    @today = Time.zone.today
    @total_notebooks = current_user.notebooks.count
    @active_notebooks = current_user.notebooks.active.count
    @today_notepad_entries = current_user.notepad_entries.where(entry_date: @today).count
    @recent_notebooks = current_user.notebooks.includes(:chapters).ordered.limit(3)
    @recent_notepad_entries = current_user.notepad_entries.recent_first.limit(3)
  end
end
