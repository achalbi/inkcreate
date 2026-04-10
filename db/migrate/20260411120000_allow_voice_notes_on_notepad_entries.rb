class AllowVoiceNotesOnNotepadEntries < ActiveRecord::Migration[8.1]
  def change
    change_column_null :voice_notes, :page_id, true

    add_reference :voice_notes, :notepad_entry, type: :uuid, foreign_key: true
    add_index :voice_notes, [:notepad_entry_id, :recorded_at]
  end
end
