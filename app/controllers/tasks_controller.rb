class TasksController < BrowserController
  before_action :require_authenticated_user!
  before_action :set_task, only: %i[show update destroy toggle_complete]

  def index
    @tasks_filter = params[:filter].presence_in(%w[all active done overdue today]) || "all"
    @tasks_sort   = params[:sort].presence_in(%w[priority due created manual]) || "manual"
    @tasks_group  = params[:group].presence_in(%w[none priority severity due notebook]) || "none"
    @tag_filter   = params[:tag].presence

    @tasks = scoped_tasks
    @task_new = current_user.tasks.new(priority: :medium, severity: :minor)

    @counts = {
      all:     current_user.tasks.count,
      active:  current_user.tasks.open.count,
      done:    current_user.tasks.done.count,
      overdue: current_user.tasks.overdue.count,
      today:   current_user.tasks.due_today.count
    }
  end

  def show
    render partial: "tasks/task_detail", locals: { task: @task }, layout: false
  end

  def create
    tags_input = params[:task].delete(:tags_input).to_s
    @task = current_user.tasks.new(task_params)
    tags_input.split(",").map(&:strip).reject(&:blank?).each { |t| @task.add_tag(t) }

    if @task.save
      redirect_to tasks_path(preserve_filter_params), notice: "Task created."
    else
      redirect_to tasks_path(preserve_filter_params), alert: @task.errors.full_messages.to_sentence
    end
  end

  def update
    tags_input = params[:task]&.delete(:tags_input)
    if tags_input.present?
      new_tags = tags_input.to_s.split(",").map(&:strip).reject(&:blank?)
      @task.tags = new_tags.to_json
    end

    if @task.update(task_params)
      respond_to do |format|
        format.html { redirect_to tasks_path(preserve_filter_params), notice: "Task updated." }
        format.json { render json: { ok: true } }
      end
    else
      respond_to do |format|
        format.html { redirect_to tasks_path(preserve_filter_params), alert: @task.errors.full_messages.to_sentence }
        format.json { render json: { ok: false, error: @task.errors.full_messages.to_sentence }, status: :unprocessable_entity }
      end
    end
  end

  def promote_from_todo
    todo_item = find_promotable_todo_item(params[:todo_item_id])
    return redirect_back(fallback_location: tasks_path, alert: "Todo item not found.") unless todo_item

    label, nb_id, ch_id, pg_id = todo_link_context(todo_item)

    task = current_user.tasks.create!(
      title:            todo_item.content,
      priority:         :medium,
      severity:         :minor,
      link_type:        "todo",
      link_label:       label,
      link_notebook_id: nb_id,
      link_chapter_id:  ch_id,
      link_page_id:     pg_id
    )

    redirect_back fallback_location: tasks_path,
                  notice: "\"#{task.title}\" added to your task list."
  end

  def link_search
    type = params[:type].presence_in(Task::LINK_TYPES)
    return render(json: []) unless type

    q = params[:q].to_s.strip
    pat = q.empty? ? "%" : "%#{q}%"

    results = case type
    when "notebook"
      current_user.notebooks
        .where("title ILIKE ?", pat)
        .order(:title).limit(10)
        .map { |n|
          { label: n.title,
            link_notebook_id: n.id,
            link_chapter_id: nil, link_page_id: nil, link_resource_id: nil }
        }

    when "chapter"
      Chapter.joins(:notebook)
        .includes(:notebook)
        .where(notebooks: { user_id: current_user.id })
        .kept
        .where("chapters.title ILIKE ?", pat)
        .order("chapters.title").limit(10)
        .map { |c|
          { label: "#{c.notebook.title} › #{c.title}",
            link_notebook_id: c.notebook_id, link_chapter_id: c.id,
            link_page_id: nil, link_resource_id: nil }
        }

    when "page"
      Page.joins(chapter: :notebook)
        .includes(chapter: :notebook)
        .where(notebooks: { user_id: current_user.id })
        .where("pages.title ILIKE ?", pat)
        .order("pages.title").limit(10)
        .map { |p|
          { label: "#{p.chapter.notebook.title} › #{p.chapter.title} › #{p.display_title}",
            link_notebook_id: p.chapter.notebook_id, link_chapter_id: p.chapter_id,
            link_page_id: p.id, link_resource_id: nil }
        }

    when "voice"
      VoiceNote.joins(page: { chapter: :notebook })
        .includes(page: { chapter: :notebook })
        .where(notebooks: { user_id: current_user.id })
        .where("voice_notes.transcript ILIKE ? OR pages.title ILIKE ?", pat, pat)
        .order("voice_notes.recorded_at DESC").limit(10)
        .map { |v|
          recorded = v.recorded_at&.strftime("%-d %b %Y") || "Unknown date"
          { label: "Voice · #{recorded} · #{v.page.display_title}",
            link_notebook_id: v.page.chapter.notebook_id,
            link_chapter_id: v.page.chapter_id,
            link_page_id: v.page_id,
            link_resource_id: v.id }
        }

    when "photo"
      current_user.captures
        .where("title ILIKE ? OR original_filename ILIKE ?", pat, pat)
        .order(captured_at: :desc).limit(10)
        .map { |c|
          { label: c.display_title,
            link_notebook_id: nil, link_chapter_id: nil,
            link_page_id: nil, link_resource_id: c.id }
        }

    when "todo"
      Page.joins(chapter: :notebook)
        .joins(:todo_list)
        .includes(chapter: :notebook)
        .where(notebooks: { user_id: current_user.id })
        .where("pages.title ILIKE ?", pat)
        .order("pages.title").limit(10)
        .map { |p|
          { label: "#{p.chapter.notebook.title} › #{p.display_title} (Todo list)",
            link_notebook_id: p.chapter.notebook_id, link_chapter_id: p.chapter_id,
            link_page_id: p.id, link_resource_id: nil }
        }

    else
      []
    end

    render json: results
  end

  def destroy
    @task.destroy
    respond_to do |format|
      format.html { redirect_to tasks_path(preserve_filter_params), notice: "Task deleted." }
      format.json { render json: { ok: true } }
    end
  end

  def toggle_complete
    if @task.completed?
      @task.mark_open!
    else
      @task.mark_complete!
    end
    redirect_to tasks_path(preserve_filter_params)
  end

  private

  def set_task
    @task = current_user.tasks.find(params[:id])
  end

  def task_params
    params.require(:task).permit(
      :title, :description, :priority, :severity,
      :due_date, :completed,
      :reminder_at, :reminder_recurrence,
      :link_type, :link_label,
      :link_notebook_id, :link_chapter_id, :link_page_id, :link_resource_id
    )
  end

  # Finds a TodoItem that belongs to the current user, via either a page or
  # a notepad entry.  Returns nil if not found or not authorised.
  def find_promotable_todo_item(id)
    return nil if id.blank?

    TodoItem
      .joins(todo_list: :page)
      .joins("INNER JOIN chapters ON chapters.id = pages.chapter_id")
      .joins("INNER JOIN notebooks ON notebooks.id = chapters.notebook_id")
      .where(notebooks: { user_id: current_user.id })
      .find_by(id: id) ||
    TodoItem
      .joins(todo_list: :notepad_entry)
      .where(notepad_entries: { user_id: current_user.id })
      .find_by(id: id)
  end

  # Builds the link label and IDs from a TodoItem's parent context.
  def todo_link_context(todo_item)
    list = todo_item.todo_list
    if list.page_id?
      page    = list.page
      chapter = page.chapter
      nb      = chapter.notebook
      label   = "#{nb.title} › #{chapter.title} › #{page.display_title}"
      [ label, nb.id, chapter.id, page.id ]
    elsif list.notepad_entry_id?
      entry = list.notepad_entry
      [ entry.display_title, nil, nil, nil ]
    else
      [ nil, nil, nil, nil ]
    end
  end

  def preserve_filter_params
    params.permit(:filter, :sort, :group, :tag).to_h
  end

  def scoped_tasks
    scope = current_user.tasks.includes(:task_subtasks)

    # Filter
    scope = case @tasks_filter
    when "active"  then scope.open
    when "done"    then scope.done
    when "overdue" then scope.overdue
    when "today"   then scope.due_today
    else scope
    end

    # Tag filter
    scope = scope.tagged_with(@tag_filter) if @tag_filter.present?

    # Sort
    case @tasks_sort
    when "priority" then scope.priority_first
    when "due"      then scope.order(Arel.sql("due_date IS NULL, due_date ASC"))
    when "created"  then scope.order(created_at: :desc)
    else                 scope.order(created_at: :desc)
    end
  end
end
