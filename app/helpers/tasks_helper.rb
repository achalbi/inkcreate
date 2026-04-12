module TasksHelper
  # Returns an ordered hash { group_label => [tasks] }
  def group_tasks_for_display(tasks, group_by)
    return { "" => tasks } if group_by.blank? || group_by == "none"

    grouped = tasks.group_by do |task|
      case group_by
      when "priority" then task.priority.humanize
      when "severity" then task.severity.humanize
      when "due"
        if task.due_date.nil?                    then "No due date"
        elsif task.due_date < Date.current       then "Overdue"
        elsif task.due_date == Date.current      then "Today"
        elsif task.due_date <= 7.days.from_now.to_date then "This week"
        else "Later"
        end
      else ""
      end
    end

    # Consistent ordering per group type
    case group_by
    when "priority"
      priority_order = %w[Urgent High Medium Low]
      grouped.sort_by { |k, _| priority_order.index(k) || 99 }.to_h
    when "severity"
      severity_order = %w[Blocker Major Minor Trivial]
      grouped.sort_by { |k, _| severity_order.index(k) || 99 }.to_h
    when "due"
      due_order = ["Overdue", "Today", "This week", "Later", "No due date"]
      grouped.sort_by { |k, _| due_order.index(k) || 99 }.to_h
    else
      grouped
    end
  end

  def priority_color_class(priority)
    { "low" => "prio-low", "medium" => "prio-medium", "high" => "prio-high", "urgent" => "prio-urgent" }.fetch(priority.to_s, "prio-medium")
  end

  def severity_badge_class(severity)
    { "trivial" => "sev-trivial", "minor" => "sev-minor", "major" => "sev-major", "blocker" => "sev-blocker" }.fetch(severity.to_s, "sev-minor")
  end

  # Returns the in-app path for a task's linked resource, or nil when IDs are missing.
  def task_link_path(task)
    return nil unless task.has_link?

    nb = task.link_notebook_id
    ch = task.link_chapter_id
    pg = task.link_page_id

    case task.link_type
    when "notebook"
      "/notebooks/#{nb}" if nb.present?
    when "chapter"
      "/notebooks/#{nb}/chapters/#{ch}" if nb.present? && ch.present?
    when "page", "voice", "todo"
      "/notebooks/#{nb}/chapters/#{ch}/pages/#{pg}" if nb.present? && ch.present? && pg.present?
    end
  end
end
