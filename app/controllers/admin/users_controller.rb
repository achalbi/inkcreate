module Admin
  class UsersController < BaseController
    def index
      @users = User.order(:created_at)
      @user_count = User.count
      @admin_count = User.admin.count
      @standard_user_count = User.user.count
      @connected_drive_count = User.where.not(google_drive_connected_at: nil).count
      @new_users_this_week = User.where(created_at: 7.days.ago..Time.current).count
      @recent_drive_users = User.where.not(google_drive_connected_at: nil).order(google_drive_connected_at: :desc).limit(5)
    end

    def update
      user = User.find(params[:id])
      new_role = user_params.fetch(:role)

      if user == current_user && new_role == "user" && User.admin.count == 1
        return redirect_to admin_users_path, alert: "You cannot demote the last admin."
      end

      user.update!(role: new_role)
      redirect_to admin_users_path, notice: "#{user.email} is now #{user.role}."
    end

    private

    def user_params
      params.require(:user).permit(:role)
    end
  end
end
