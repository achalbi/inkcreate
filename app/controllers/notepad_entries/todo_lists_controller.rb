module NotepadEntries
  class TodoListsController < BaseController
    def create
      todo_list = @notepad_entry.todo_list || @notepad_entry.build_todo_list
      todo_list.assign_attributes(todo_list_params)
      todo_list.save!

      render_section(message: "To-do list ready.")
    rescue ActiveRecord::RecordInvalid => error
      render_error(error.record.errors.full_messages.to_sentence)
    end

    def update
      todo_list = @notepad_entry.todo_list || @notepad_entry.build_todo_list
      todo_list.assign_attributes(todo_list_params)
      todo_list.save!

      render_section(message: "To-do list updated.")
    rescue ActiveRecord::RecordInvalid => error
      render_error(error.record.errors.full_messages.to_sentence)
    end

    private

    def todo_list_params
      params.fetch(:todo_list, {}).permit(:enabled, :hide_completed)
    end

    def render_section(message:)
      @notepad_entry.reload

      if request.format.json?
        render json: {
          ok: true,
          message: message,
          html: render_to_string(
            partial: todo_list_partial,
            formats: [:html],
            locals: { notepad_entry: @notepad_entry }
          )
        }
      else
        redirect_to notepad_entry_path(@notepad_entry), notice: message
      end
    end

    def render_error(message)
      if request.format.json?
        render json: { ok: false, error: message }, status: :unprocessable_entity
      else
        redirect_to notepad_entry_path(@notepad_entry), alert: message
      end
    end

    def todo_list_partial
      referer = request.referer.to_s
      return "notepad_entries/todo_list_section" if referer.include?(edit_notepad_entry_path(@notepad_entry))
      return "notepad_entries/todo_list_document_section" if referer.include?(notepad_entry_path(@notepad_entry))

      "notepad_entries/todo_list_section"
    end
  end
end
