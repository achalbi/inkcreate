class ExtendTasksWithSeverityRemindersTagsLinks < ActiveRecord::Migration[8.0]
  def change
    add_column :tasks, :severity, :integer, default: 0, null: false
    add_column :tasks, :reminder_at, :datetime
    add_column :tasks, :reminder_recurrence, :string, default: "none", null: false
    add_column :tasks, :tags, :text, default: "[]", null: false  # JSON array
    add_column :tasks, :link_type, :string       # notebook | chapter | page | voice | photo | todo
    add_column :tasks, :link_label, :string
    add_column :tasks, :link_notebook_id, :string
    add_column :tasks, :link_chapter_id, :string
    add_column :tasks, :link_page_id, :string
    add_column :tasks, :link_resource_id, :string
  end
end
