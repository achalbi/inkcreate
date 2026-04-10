class CreateVoiceNotes < ActiveRecord::Migration[8.1]
  def change
    create_table :voice_notes, id: :uuid do |t|
      t.references :page, null: false, foreign_key: true, type: :uuid
      t.integer :duration_seconds, null: false, default: 0
      t.datetime :recorded_at, null: false
      t.bigint :byte_size, null: false, default: 0
      t.string :mime_type, null: false
      t.text :transcript
      t.timestamps
    end

    add_index :voice_notes, [:page_id, :recorded_at]
  end
end
