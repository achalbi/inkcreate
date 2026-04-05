class NotebookSerializer
  def initialize(notebook)
    @notebook = notebook
  end

  def as_json(*)
    {
      id: notebook.id,
      title: notebook.title,
      name: notebook.title,
      slug: notebook.slug,
      description: notebook.description,
      status: notebook.status,
      color_token: notebook.color_token,
      archived_at: notebook.archived_at,
      chapter_count: notebook.chapters.count,
      page_count: notebook.pages.count,
      capture_count: notebook.captures.count,
      created_at: notebook.created_at,
      updated_at: notebook.updated_at
    }
  end

  private

  attr_reader :notebook
end
