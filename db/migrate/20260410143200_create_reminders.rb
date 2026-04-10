class CreateReminders < ActiveRecord::Migration[8.1]
  def change
    create_table :reminders, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.references :target, polymorphic: true, type: :uuid
      t.string :title, null: false
      t.text :note
      t.datetime :fire_at, null: false
      t.integer :status, null: false, default: 0
      t.datetime :last_triggered_at
      t.datetime :snooze_until
      t.timestamps
    end

    add_index :reminders, [:user_id, :status, :fire_at]
    add_index :reminders, [:status, :fire_at]
  end
end
