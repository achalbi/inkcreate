class ProjectsController < BrowserController
  before_action :require_authenticated_user!

  def index
    @project = current_user.projects.new(color: "#17392d")
    @projects = current_user.projects.active.includes(:captures, :tasks).recent_first
  end

  def create
    project = current_user.projects.create!(project_params)
    redirect_to project_path(project), notice: "Project created."
  end

  def show
    @project = current_user.projects.find(params[:id])
    @captures = @project.captures.includes(:tags, :ai_summaries).recent_first
    @tasks = @project.tasks.recent_first.limit(12)
    @attachments = current_user.attachments.joins(:capture).where(captures: { project_id: @project.id }).recent_first.limit(16)
  end

  private

  def project_params
    params.require(:project).permit(:title, :description, :color)
  end
end
