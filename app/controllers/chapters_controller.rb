class ChaptersController < BrowserController
  before_action :require_authenticated_user!
  before_action :set_notebook
  before_action :set_chapter, only: %i[show edit update destroy move restore]

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
    if @chapter.pages.exists? && current_user.ensure_app_setting!.keep_deleted_chapters_recoverable?
      @chapter.soft_delete!
      redirect_to notebook_path(@notebook), notice: "Chapter moved to deleted chapters because it still contains pages."
    elsif @chapter.pages.exists?
      @chapter.destroy!
      redirect_to notebook_path(@notebook), notice: "Chapter deleted with its pages."
    else
      @chapter.destroy!
      redirect_to notebook_path(@notebook), notice: "Chapter deleted."
    end
  end

  def restore
    @chapter.restore!
    redirect_to notebook_path(@notebook), notice: "Chapter restored."
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
    @chapter = @notebook.all_chapters.find(params[:id])
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
