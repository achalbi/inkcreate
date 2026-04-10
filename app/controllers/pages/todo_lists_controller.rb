module Pages
  class TodoListsController < BaseController
    def create
      todo_list = @page.todo_list || @page.build_todo_list
      todo_list.assign_attributes(todo_list_params)
      todo_list.save!

      render_section(message: "To-do list ready.")
    rescue ActiveRecord::RecordInvalid => error
      render_error(error.record.errors.full_messages.to_sentence)
    end

    def update
      todo_list = @page.todo_list || @page.build_todo_list
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
      @page.reload

      if request.format.json?
        render json: {
          ok: true,
          message: message,
          html: render_to_string(
            partial: "pages/todo_list_section",
            formats: [:html],
            locals: { notebook: @notebook, chapter: @chapter, page: @page }
          )
        }
      else
        redirect_to notebook_chapter_page_path(@notebook, @chapter, @page), notice: message
      end
    end

    def render_error(message)
      if request.format.json?
        render json: { ok: false, error: message }, status: :unprocessable_entity
      else
        redirect_to notebook_chapter_page_path(@notebook, @chapter, @page), alert: message
      end
    end
  end
end
