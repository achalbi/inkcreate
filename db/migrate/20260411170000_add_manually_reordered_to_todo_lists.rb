class AddManuallyReorderedToTodoLists < ActiveRecord::Migration[8.1]
  def change
    add_column :todo_lists, :manually_reordered, :boolean, null: false, default: false
  end
end
