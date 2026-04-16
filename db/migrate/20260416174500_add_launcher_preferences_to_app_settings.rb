class AddLauncherPreferencesToAppSettings < ActiveRecord::Migration[8.0]
  def change
    add_column :app_settings, :launcher_preferences, :jsonb, null: false, default: {}
  end
end
