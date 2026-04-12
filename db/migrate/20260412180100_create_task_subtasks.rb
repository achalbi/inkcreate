class CreateTaskSubtasks < ActiveRecord::Migration[8.0]
  def change
    create_table :task_subtasks, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :task_id, null: false
      t.string :title, null: false
      t.boolean :completed, default: false, null: false
      t.datetime :completed_at
      t.integer :position, default: 0, null: false
      t.timestamps
    end

    add_index :task_subtasks, :task_id
    add_index :task_subtasks, [ :task_id, :position ]
    add_foreign_key :task_subtasks, :tasks
  end
end
