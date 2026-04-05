class BuildNotebookAndNotepadStructure < ActiveRecord::Migration[8.1]
  def up
    add_column :notebooks, :title, :string
    add_column :notebooks, :description, :text
    add_column :notebooks, :status, :integer, null: false, default: 0
    add_index :notebooks, [:user_id, :status]

    execute <<~SQL
      UPDATE notebooks
      SET title = COALESCE(NULLIF(name, ''), 'Untitled notebook')
    SQL

    execute <<~SQL
      UPDATE notebooks
      SET status = CASE WHEN archived_at IS NULL THEN 0 ELSE 1 END
    SQL

    change_column_null :notebooks, :title, false

    create_table :chapters, id: :uuid do |t|
      t.references :notebook, null: false, foreign_key: true, type: :uuid
      t.string :title, null: false
      t.text :description
      t.integer :position, null: false
      t.timestamps
    end

    add_index :chapters, [:notebook_id, :position]

    create_table :pages, id: :uuid do |t|
      t.references :chapter, null: false, foreign_key: true, type: :uuid
      t.string :title, null: false
      t.text :notes
      t.date :captured_on
      t.integer :position, null: false
      t.timestamps
    end

    add_index :pages, [:chapter_id, :position]

    create_table :notepad_entries, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :title
      t.text :notes
      t.date :entry_date, null: false
      t.timestamps
    end

    add_index :notepad_entries, [:user_id, :entry_date]
  end

  def down
    drop_table :notepad_entries
    drop_table :pages
    drop_table :chapters

    remove_index :notebooks, [:user_id, :status]
    remove_column :notebooks, :status
    remove_column :notebooks, :description
    remove_column :notebooks, :title
  end
end
