class CreateGlobalSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :global_settings, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.boolean :password_auth_enabled, default: true, null: false
      t.timestamps
    end
  end
end
