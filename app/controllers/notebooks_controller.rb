class NotebooksController < BrowserController
  NOTEBOOKS_PER_PAGE = 6

  before_action :require_authenticated_user!
  before_action :set_notebook, only: %i[show edit update archive unarchive]

  def index
    @notebook_scope = notebook_scope
    @query = params[:q].to_s.squish

    active_scope = filtered_notebooks(current_user.notebooks.active)
    archived_scope = filtered_notebooks(current_user.notebooks.archived)

    @active_notebooks_all = notebook_collection_for(active_scope)
    @archived_notebooks_all = notebook_collection_for(archived_scope)

    @active_notebook_count = @active_notebooks_all.size
    @archived_notebook_count = @archived_notebooks_all.size

    @active_total_pages = total_pages_for(@active_notebook_count)
    @archived_total_pages = total_pages_for(@archived_notebook_count)

    @active_page = bounded_page_param(:page, @active_total_pages)
    @archived_page = bounded_page_param(:page, @archived_total_pages)

    @active_notebooks = paginated_collection(@active_notebooks_all, @active_page)
    @archived_notebooks = paginated_collection(@archived_notebooks_all, @archived_page)
  end

  def show
    @chapters = @notebook.chapters.includes(:pages)
    @deleted_chapters = @notebook.deleted_chapters.includes(:pages)
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

  def positive_page_param(key)
    page = params[key].to_i
    page.positive? ? page : 1
  end

  def bounded_page_param(key, total_pages)
    [positive_page_param(key), total_pages].min
  end

  def total_pages_for(count)
    [(count.to_f / NOTEBOOKS_PER_PAGE).ceil, 1].max
  end

  def paginated_collection(collection, page)
    collection.slice((page - 1) * NOTEBOOKS_PER_PAGE, NOTEBOOKS_PER_PAGE) || []
  end

  def notebook_scope
    params[:scope] == "archived" ? "archived" : "current"
  end

  def filtered_notebooks(scope)
    return scope unless @query.present?

    search_term = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"

    scope
      .left_outer_joins(:chapters)
      .where(
        "notebooks.title ILIKE :term OR notebooks.name ILIKE :term OR notebooks.description ILIKE :term OR chapters.title ILIKE :term OR chapters.description ILIKE :term",
        term: search_term
      )
      .distinct
  end

  def notebook_collection_for(scope)
    scope.includes(chapters: :pages).ordered.to_a
  end
end
