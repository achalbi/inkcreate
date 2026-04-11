module NotepadEntries
  class BaseController < BrowserController
    before_action :require_authenticated_user!
    before_action :ensure_todo_lists_supported!
    before_action :set_notepad_entry

    private

    def set_notepad_entry
      scope = current_user.notepad_entries
      includes = []

      if Reminder.schema_ready?
        includes << { todo_list: { todo_items: :reminder } }
      else
        includes << { todo_list: :todo_items }
      end

      scope = scope.includes(*includes) if includes.any?
      @notepad_entry = scope.find(params[:notepad_entry_id])
    end

    def ensure_todo_lists_supported!
      head :not_found unless TodoList.schema_ready? && TodoItem.schema_ready?
    end
  end
end
