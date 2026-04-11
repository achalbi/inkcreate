class AddNotepadEntrySupportToTodoLists < ActiveRecord::Migration[8.1]
  def change
    change_column_null :todo_lists, :page_id, true

    add_reference :todo_lists, :notepad_entry, type: :uuid, index: false, foreign_key: true
    add_index :todo_lists, :notepad_entry_id, unique: true, where: "notepad_entry_id IS NOT NULL"

    add_check_constraint(
      :todo_lists,
      "(CASE WHEN page_id IS NOT NULL THEN 1 ELSE 0 END + CASE WHEN notepad_entry_id IS NOT NULL THEN 1 ELSE 0 END) = 1",
      name: "todo_lists_exactly_one_owner"
    )
  end
end
