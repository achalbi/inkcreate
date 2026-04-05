Rails.application.config.filter_parameters += %i[
  password
  password_confirmation
  google_drive_access_token
  google_drive_refresh_token
  authorization
]
