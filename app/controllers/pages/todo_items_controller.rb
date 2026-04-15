module Pages
  class TodoItemsController < BaseController
    include DriveRecordExportScheduling

    before_action :set_todo_list
    before_action :set_todo_item, only: %i[update destroy toggle reorder]

    def create
      @todo_item = @todo_list.todo_items.new(todo_item_params)
      @todo_item.save!

      render_section(message: "To-do item added.")
    rescue ActiveRecord::RecordInvalid => error
      render_error(error.record.errors.full_messages.to_sentence)
    end

    def update
      @todo_item.update!(todo_item_params)
      render_section(message: "To-do item updated.")
    rescue ActiveRecord::RecordInvalid => error
      render_error(error.record.errors.full_messages.to_sentence)
    end

    def destroy
      @todo_item.destroy!
      normalize_positions!
      render_section(message: "To-do item removed.")
    end

    def toggle
      @todo_item.toggle_completion!
      render_section(message: "To-do item updated.")
    end

    def reorder
      new_position = params.require(:todo_item).fetch(:position).to_i
      with_suppressed_drive_record_export_callbacks do
        move_to_position!(@todo_item, new_position)
      end
      schedule_drive_export(@page)
      render_section(message: "To-do item reordered.")
    rescue ActionController::ParameterMissing
      render_error("Choose a new position for the to-do item.")
    end

    private

    def set_todo_list
      @todo_list = @page.todo_list || @page.create_todo_list!
      @todo_list.update!(enabled: true) unless @todo_list.enabled?
    end

    def set_todo_item
      @todo_item = @todo_list.todo_items.find(params[:id])
    end

    def todo_item_params
      params.require(:todo_item).permit(:content)
    end

    def move_to_position!(item, requested_position)
      items = @todo_list.display_todo_items.to_a
      requested_position = requested_position.clamp(1, items.size)

      TodoItem.transaction do
        remaining_items = items.reject { |existing_item| existing_item.id == item.id }
        remaining_items.insert(requested_position - 1, item)

        remaining_items.each_with_index do |todo_item, index|
          todo_item.update!(position: index + 1)
        end

        @todo_list.track_manual_reordering!
      end
    end

    def normalize_positions!
      @todo_list.todo_items.ordered.each_with_index do |todo_item, index|
        next if todo_item.position == index + 1

        todo_item.update_column(:position, index + 1)
      end
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
