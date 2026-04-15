class DefaultAppSettingsBackupEnabledToTrue < ActiveRecord::Migration[8.1]
  def up
    change_column_default :app_settings, :backup_enabled, from: false, to: true

    execute <<~SQL.squish
      UPDATE app_settings
      SET backup_enabled = TRUE,
          updated_at = CURRENT_TIMESTAMP
      WHERE backup_enabled = FALSE
        AND backup_provider IS NULL
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE app_settings
      SET backup_enabled = FALSE,
          updated_at = CURRENT_TIMESTAMP
      WHERE backup_enabled = TRUE
        AND backup_provider IS NULL
    SQL

    change_column_default :app_settings, :backup_enabled, from: true, to: false
  end
end
