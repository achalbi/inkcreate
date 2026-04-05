class CreateGoogleDriveExports < ActiveRecord::Migration[8.1]
  def change
    create_table :google_drive_exports, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.references :exportable, null: false, polymorphic: true, type: :uuid
      t.integer :status, null: false, default: 0
      t.string :drive_folder_id
      t.string :remote_folder_id
      t.string :remote_notes_file_id
      t.string :remote_manifest_file_id
      t.jsonb :remote_photo_file_ids, null: false, default: {}
      t.datetime :last_attempted_at
      t.datetime :exported_at
      t.text :error_message
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :google_drive_exports, [:user_id, :status]
    add_index :google_drive_exports, [:exportable_type, :exportable_id], unique: true
  end
end
