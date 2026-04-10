module Pages
  class BaseController < BrowserController
    before_action :require_authenticated_user!
    before_action :set_notebook
    before_action :set_chapter
    before_action :set_page

    private

    def set_notebook
      @notebook = current_user.notebooks.find(params[:notebook_id])
    end

    def set_chapter
      @chapter = @notebook.all_chapters.find(params[:chapter_id])
    end

    def set_page
      scope = @chapter.pages
      includes = []
      includes << { voice_notes: [audio_attachment: :blob] } if VoiceNote.schema_ready?

      if TodoList.schema_ready? && TodoItem.schema_ready?
        includes << if Reminder.schema_ready?
          { todo_list: { todo_items: :reminder } }
        else
          { todo_list: :todo_items }
        end
      end

      scope = scope.includes(*includes) if includes.any?
      @page = scope.find(params[:page_id])
    end
  end
end
