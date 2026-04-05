class CaptureSearchQuery
  def initialize(user:, query:, notebook_id: nil, page_template_key: nil, tag: nil, project_id: nil, date: nil, page_type: nil)
    @user = user
    @query = query.to_s.strip
    @notebook_id = notebook_id
    @page_template_key = page_template_key
    @tag = tag
    @project_id = project_id
    @date = date
    @page_type = page_type
  end

  def call
    scope = user.captures.includes(:page_template, :tags, :ocr_results).recent_first
    scope = scope.where(notebook_id: notebook_id) if notebook_id.present?
    scope = scope.joins(:page_template).where(page_templates: { key: page_template_key }) if page_template_key.present?
    scope = scope.joins(:tags).where(tags: { name: tag }) if tag.present?
    scope = scope.where(project_id: project_id) if project_id.present?
    scope = scope.where("DATE(COALESCE(captured_at, created_at)) = ?", date) if date.present?
    scope = scope.where(page_type: page_type) if page_type.present?

    return scope unless query.present?

    quoted_query = ActiveRecord::Base.connection.quote(query)

    scope
      .where("captures.search_vector @@ websearch_to_tsquery('english', #{quoted_query})")
      .order(Arel.sql("ts_rank(captures.search_vector, websearch_to_tsquery('english', #{quoted_query})) DESC"))
  end

  private

  attr_reader :user, :query, :notebook_id, :page_template_key, :tag, :project_id, :date, :page_type
end
