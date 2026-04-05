class AddDeletedAtToChapters < ActiveRecord::Migration[8.1]
  def change
    add_column :chapters, :deleted_at, :datetime
    add_index :chapters, [:notebook_id, :deleted_at]
  end
end
