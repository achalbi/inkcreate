class GlobalSetting < ApplicationRecord
  # Singleton — only one row should ever exist.
  # Use GlobalSetting.instance to read, GlobalSetting.instance.update! to write.
  def self.instance
    first_or_create!(password_auth_enabled: true)
  end

  def self.password_auth_enabled?
    instance.password_auth_enabled?
  end
end
