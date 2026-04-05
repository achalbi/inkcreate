class ChaptersController < BrowserController
  before_action :require_authenticated_user!
  before_action :set_notebook
  before_action :set_chapter, only: %i[show edit update destroy move]

  def show
    @pages = @chapter.pages.with_attached_photos
  end

  def new
    @chapter = @notebook.chapters.new
  end

  def create
    @chapter = @notebook.chapters.new(chapter_params)

    if @chapter.save
      redirect_to notebook_path(@notebook), notice: "Chapter created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @chapter.update(chapter_params)
      redirect_to notebook_chapter_path(@notebook, @chapter), notice: "Chapter updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @chapter.destroy!
    redirect_to notebook_path(@notebook), notice: "Chapter deleted."
  end

  def move
    move_within_scope(@notebook.chapters.ordered, @chapter, params[:direction])
    redirect_to notebook_path(@notebook), notice: "Chapter order updated."
  end

  private

  def set_notebook
    @notebook = current_user.notebooks.find(params[:notebook_id])
  end

  def set_chapter
    @chapter = @notebook.chapters.find(params[:id])
  end

  def chapter_params
    params.require(:chapter).permit(:title, :description)
  end

  def move_within_scope(scope, record, direction)
    items = scope.to_a
    index = items.index(record)
    return if index.nil?

    swap_index = direction == "up" ? index - 1 : index + 1
    return if swap_index.negative? || swap_index >= items.length

    other = items[swap_index]

    record.class.transaction do
      record_position = record.position
      record.update!(position: other.position)
      other.update!(position: record_position)
    end
  end
end
