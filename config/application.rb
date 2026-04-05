require_relative "boot"

require "rails"
require "active_job/railtie"
require "active_model/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "propshaft"
require "propshaft/railtie"

Bundler.require(*Rails.groups)

module Inkcreate
  class Application < Rails::Application
    config.load_defaults 8.1
    config.api_only = false

    config.active_job.queue_adapter = :sidekiq
    config.autoload_paths << Rails.root.join("lib")

    config.middleware.use Rack::Attack

    config.action_dispatch.cookies_same_site_protection = :lax
    config.session_store :cookie_store,
      key: "_inkcreate_session",
      same_site: :lax,
      secure: Rails.env.production?,
      httponly: true
    config.filter_parameters += %i[
      password
      password_confirmation
      google_drive_access_token
      google_drive_refresh_token
      authorization
      token
    ]

    config.log_tags = [:request_id]
    config.active_storage.variant_processor = :vips

    base_logger = ActiveSupport::Logger.new($stdout)
    base_logger.formatter = proc do |severity, timestamp, _progname, message|
      payload = {
        severity: severity,
        time: timestamp.utc.iso8601(3),
        service: "inkcreate-api",
        message: message.is_a?(Hash) ? message : { msg: message }
      }

      "#{Oj.dump(payload, mode: :compat)}\n"
    end
    config.logger = ActiveSupport::TaggedLogging.new(base_logger)

    config.generators do |g|
      g.orm :active_record, primary_key_type: :uuid
      g.test_framework :rspec, fixture: false
      g.assets false
      g.helper false
    end
  end
end
