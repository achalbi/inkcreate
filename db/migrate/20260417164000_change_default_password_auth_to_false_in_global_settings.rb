class ChangeDefaultPasswordAuthToFalseInGlobalSettings < ActiveRecord::Migration[8.0]
  def up
    change_column_default :global_settings, :password_auth_enabled, from: true, to: false
    execute <<~SQL
      UPDATE global_settings
      SET password_auth_enabled = FALSE
      WHERE password_auth_enabled = TRUE
    SQL
  end

  def down
    change_column_default :global_settings, :password_auth_enabled, from: false, to: true
  end
end
