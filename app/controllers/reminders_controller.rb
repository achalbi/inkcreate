class RemindersController < BrowserController
  before_action :require_authenticated_user!
  before_action :require_reminders_schema!
  before_action :set_reminder, only: %i[show edit update destroy dismiss snooze]

  def index
    load_index_state
  end

  def show; end

  def edit; end

  def create
    @reminder = reminder_for_create
    new_record = @reminder.new_record?
    @reminder.assign_attributes(reminder_attributes)
    add_invalid_target_error(@reminder)

    if @reminder.errors.empty? && @reminder.save
      redirect_to reminder_return_path(@reminder), notice: (new_record ? "Reminder created." : "Reminder updated.")
    else
      render_failed_create
    end
  end

  def update
    @reminder.assign_attributes(reminder_attributes)
    add_invalid_target_error(@reminder)

    if @reminder.errors.empty? && @reminder.save
      redirect_to reminder_return_path(@reminder), notice: "Reminder updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def dismiss
    @reminder.dismiss!
    redirect_back fallback_location: dashboard_path, notice: "Reminder dismissed."
  end

  def snooze
    @reminder.snooze!(snooze_target_time)
    redirect_back fallback_location: reminder_return_path(@reminder), notice: "Reminder snoozed."
  end

  def destroy
    @reminder.destroy!
    redirect_to reminders_path, notice: "Reminder deleted."
  end

  private

  def set_reminder
    @reminder = current_user.reminders.find(params[:id])
  end

  def reminder_params
    params.require(:reminder).permit(:title, :note, :fire_at_local, :target_type, :target_id)
  end

  def reminder_attributes
    attrs = reminder_params.except(:fire_at_local, :target_type, :target_id)
    attrs[:fire_at] = parsed_fire_at
    attrs[:target] = resolved_target
    attrs
  end

  def parsed_fire_at
    Time.zone.parse(reminder_params[:fire_at_local].to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def resolved_target
    return if reminder_params[:target_type].blank? || reminder_params[:target_id].blank?
    return unless reminder_params[:target_type] == "TodoItem"

    @resolved_target ||= begin
      candidate = TodoItem
        .includes(todo_list: [:page, :notepad_entry])
        .find_by(id: reminder_params[:target_id])

      candidate if candidate&.user == current_user
    end
  end

  def reminder_for_create
    return current_user.reminders.new unless resolved_target.present?

    current_user.reminders.find_or_initialize_by(target: resolved_target)
  end

  def add_invalid_target_error(reminder)
    return unless target_requested?
    return if resolved_target.present?

    reminder.errors.add(:base, "Choose a valid to-do item for this reminder.")
  end

  def target_requested?
    reminder_params[:target_type].present? || reminder_params[:target_id].present?
  end

  def reminder_return_path(reminder)
    reminder.standalone? ? reminders_path : reminder.destination_path
  end

  def snooze_target_time
    if params[:reminder].present? && params[:reminder][:snooze_until_local].present?
      Time.zone.parse(params[:reminder][:snooze_until_local].to_s)
    else
      minutes = params[:minutes].to_i
      minutes = 10 if minutes <= 0
      minutes.minutes.from_now
    end
  rescue ArgumentError, TypeError
    10.minutes.from_now
  end

  def load_home_state
    @today = Time.zone.today
    @reminders_available = true
    @new_reminder = @reminder
    @total_notebooks = current_user.notebooks.count
    @active_notebooks = current_user.notebooks.active.count
    @today_notepad_entries = current_user.notepad_entries.where(entry_date: @today).count
    @recent_notebooks = current_user.notebooks.includes(:chapters).ordered.limit(2)
    @recent_notepad_entries = current_user.notepad_entries.recent_first.limit(2)
    upcoming_reminders = current_user.reminders.upcoming_first
    @upcoming_reminders_count = upcoming_reminders.count
    @upcoming_reminders = upcoming_reminders.limit(2)
  end

  def load_index_state
    expire_overdue_history_reminders!
    @new_reminder ||= current_user.reminders.new
    @upcoming_reminders = current_user.reminders.upcoming_first
    @historical_reminders = current_user.reminders.history_recent_first
  end

  def render_failed_create
    case params[:form_context]
    when "reminders_index"
      @new_reminder = @reminder
      load_index_state
      render :index, status: :unprocessable_entity
    else
      load_home_state
      render "home/show", status: :unprocessable_entity
    end
  end

  def require_reminders_schema!
    return if Reminder.schema_ready?

    redirect_to dashboard_path, alert: "Run the latest database migrations to enable reminders."
  end

  def expire_overdue_history_reminders!
    current_time = Time.current

    current_user.reminders
      .where(status: [
        Reminder.statuses[:pending],
        Reminder.statuses[:snoozed],
        Reminder.statuses[:dismissed]
      ])
      .where(fire_at: ..current_time)
      .update_all(
        status: Reminder.statuses[:expired],
        snooze_until: nil,
        updated_at: current_time
      )
  end
end
