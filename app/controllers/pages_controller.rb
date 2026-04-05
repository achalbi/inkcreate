class PagesController < BrowserController
  before_action :require_authenticated_user!
  before_action :set_notebook
  before_action :set_chapter
  before_action :set_page, only: %i[show edit update destroy move destroy_photo]

  def show; end

  def new
    @page = @chapter.pages.new(captured_on: Date.current)
  end

  def create
    @page = @chapter.pages.new(page_attributes)

    if @page.save
      attach_photos(@page)
      redirect_to notebook_chapter_page_path(@notebook, @chapter, @page), notice: "Page created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @page.update(page_attributes)
      attach_photos(@page)
      redirect_to notebook_chapter_page_path(@notebook, @chapter, @page), notice: "Page updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @page.destroy!
    redirect_to notebook_chapter_path(@notebook, @chapter), notice: "Page deleted."
  end

  def move
    move_within_scope(@chapter.pages.ordered, @page, params[:direction])
    redirect_to notebook_chapter_path(@notebook, @chapter), notice: "Page order updated."
  end

  def destroy_photo
    attachment = @page.photos.attachments.find(params[:attachment_id])
    attachment.purge
    redirect_to notebook_chapter_page_path(@notebook, @chapter, @page), notice: "Photo removed."
  end

  private

  def set_notebook
    @notebook = current_user.notebooks.find(params[:notebook_id])
  end

  def set_chapter
    @chapter = @notebook.chapters.find(params[:chapter_id])
  end

  def set_page
    @page = @chapter.pages.with_attached_photos.find(params[:id])
  end

  def page_params
    params.require(:page).permit(:title, :notes, :captured_on, photos: [])
  end

  def page_attributes
    page_params.except(:photos)
  end

  def attach_photos(page)
    files = Array(page_params[:photos]).reject(&:blank?)
    page.photos.attach(files) if files.any?
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
