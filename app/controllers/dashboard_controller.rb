class DashboardController < BrowserController
  before_action :require_authenticated_user!

  def show
    @notebook_count = current_user.notebooks.count
    @capture_count = current_user.captures.count
    @tag_count = current_user.tags.count
    @drive_connected = current_user.google_drive_connected?
    @api_endpoints = [
      ["GET", "/api/v1/notebooks"],
      ["POST", "/api/v1/upload_urls"],
      ["POST", "/api/v1/captures"],
      ["GET", "/api/v1/search"]
    ]
  end
end
