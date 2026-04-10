class CreateTodoListsAndItems < ActiveRecord::Migration[8.1]
  def change
    create_table :todo_lists, id: :uuid do |t|
      t.references :page, null: false, foreign_key: true, type: :uuid, index: { unique: true }
      t.boolean :enabled, null: false, default: true
      t.boolean :hide_completed, null: false, default: false
      t.timestamps
    end

    create_table :todo_items, id: :uuid do |t|
      t.references :todo_list, null: false, foreign_key: true, type: :uuid
      t.string :content, null: false
      t.boolean :completed, null: false, default: false
      t.datetime :completed_at
      t.integer :position, null: false, default: 1
      t.timestamps
    end

    add_index :todo_items, [:todo_list_id, :position]
  end
end
