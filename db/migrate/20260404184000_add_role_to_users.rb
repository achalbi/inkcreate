class AddRoleToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :role, :integer, null: false, default: 0
    add_index :users, :role

    execute <<~SQL
      UPDATE users
      SET role = 1
      WHERE id IN (
        SELECT id
        FROM users
        ORDER BY created_at ASC, id ASC
        LIMIT 1
      )
    SQL
  end

  def down
    remove_index :users, :role
    remove_column :users, :role
  end
end
