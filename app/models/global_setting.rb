class GlobalSetting < ApplicationRecord
  # Singleton — only one row should ever exist.
  # Use GlobalSetting.instance to read, GlobalSetting.instance.update! to write.
  def self.instance
    first_or_create!(password_auth_enabled: false)
  end

  def self.password_auth_enabled?
    return true if password_auth_forced_on?

    instance.password_auth_enabled?
  rescue ActiveRecord::StatementInvalid, PG::UndefinedTable
    # Table hasn't been created yet (migration pending). Default to enabled
    # so the app stays functional until `rails db:migrate` is run.
    true
  end

  def self.google_auth_configured?
    defined?(::Auth::GoogleOauthClient) && ::Auth::GoogleOauthClient.configured?
  rescue NameError
    false
  end

  def self.password_auth_forced_on?
    development_env? || !google_auth_configured?
  end

  def self.development_env?
    Rails.env.development?
  end
end
