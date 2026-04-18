class AddContactsDataToPagesAndNotepadEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :pages, :contacts_data, :jsonb, default: [], null: false
    add_column :notepad_entries, :contacts_data, :jsonb, default: [], null: false
  end
end
