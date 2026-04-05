class UserSerializer
  def initialize(user)
    @user = user
  end

  def as_json(*)
    {
      id: user.id,
      email: user.email,
      role: user.role,
      google_drive_connected: user.google_drive_connected_at.present?,
      time_zone: user.time_zone,
      locale: user.locale
    }
  end

  private

  attr_reader :user
end
