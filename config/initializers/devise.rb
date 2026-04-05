Devise.setup do |config|
  require "devise/orm/active_record"

  config.mailer_sender = ENV.fetch("DEVISE_MAILER_SENDER", "noreply@inkcreate.local")
  config.case_insensitive_keys = [:email]
  config.strip_whitespace_keys = [:email]
  config.skip_session_storage = []
  config.parent_controller = "ApplicationController"
  config.sign_out_via = :delete
  config.navigational_formats = []

  config.stretches = Rails.env.test? ? 1 : 12
end
