class NotebooksController < BrowserController
  before_action :require_authenticated_user!
  before_action :set_notebook, only: %i[show edit update archive unarchive]

  def index
    notebooks = current_user.notebooks.includes(:chapters).ordered
    @active_notebooks = notebooks.select(&:status_active?)
    @archived_notebooks = notebooks.select(&:status_archived?)
  end

  def show
    @chapters = @notebook.chapters.includes(:pages)
  end

  def new
    @notebook = current_user.notebooks.new(status: :active)
  end

  def create
    @notebook = current_user.notebooks.new(notebook_params)

    if @notebook.save
      redirect_to notebook_path(@notebook), notice: "Notebook created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @notebook.update(notebook_params)
      redirect_to notebook_path(@notebook), notice: "Notebook updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def archive
    @notebook.update!(status: :archived)
    redirect_to notebooks_path, notice: "Notebook archived."
  end

  def unarchive
    @notebook.update!(status: :active)
    redirect_to notebooks_path, notice: "Notebook restored."
  end

  private

  def set_notebook
    @notebook = current_user.notebooks.find(params[:id])
  end

  def notebook_params
    params.require(:notebook).permit(:title, :description, :status)
  end
end
