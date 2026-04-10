class CreateDevices < ActiveRecord::Migration[8.1]
  def change
    create_table :devices, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :label
      t.string :user_agent, null: false, default: ""
      t.boolean :push_enabled, null: false, default: false
      t.text :push_endpoint
      t.string :push_p256dh_key
      t.string :push_auth_key
      t.datetime :last_seen_at
      t.timestamps
    end

    add_index :devices, [:user_id, :push_enabled]
    add_index :devices, :push_endpoint, unique: true, where: "push_endpoint IS NOT NULL"
  end
end
