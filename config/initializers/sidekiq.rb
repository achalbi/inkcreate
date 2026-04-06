if ENV.fetch("JOB_BACKEND", "sidekiq") != "cloud_tasks" || ENV["REDIS_URL"].present?
  sidekiq_redis = {
    url: ENV.fetch("REDIS_URL"),
    network_timeout: 5,
    pool_timeout: 5
  }

  Sidekiq.configure_server do |config|
    config.redis = sidekiq_redis
  end

  Sidekiq.configure_client do |config|
    config.redis = sidekiq_redis
  end
end
