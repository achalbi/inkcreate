return unless ENV["SENTRY_DSN"].present?

Sentry.init do |config|
  config.dsn = ENV.fetch("SENTRY_DSN")
  config.breadcrumbs_logger = %i[active_support_logger http_logger]
  config.environment = ENV.fetch("RAILS_ENV", "development")
  config.enabled_environments = %w[staging production]
  config.traces_sample_rate = ENV.fetch("SENTRY_TRACES_SAMPLE_RATE", 0.1).to_f
end
