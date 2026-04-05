class ExpandProductFoundation < ActiveRecord::Migration[8.1]
  def change
    create_table :projects, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :title, null: false
      t.text :description
      t.string :color, null: false, default: "#17392d"
      t.string :slug, null: false
      t.datetime :archived_at
      t.timestamps
    end

    add_index :projects, [:user_id, :slug], unique: true
    add_index :projects, [:user_id, :archived_at]

    create_table :daily_logs, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.date :entry_date, null: false
      t.string :title
      t.text :summary
      t.text :quick_note
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :daily_logs, [:user_id, :entry_date], unique: true

    create_table :physical_pages, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.integer :page_number, null: false
      t.string :template_type, null: false
      t.string :label
      t.text :notes
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    add_index :physical_pages, [:user_id, :page_number], unique: true

    change_table :captures, bulk: true do |t|
      t.text :description
      t.string :page_type
      t.references :physical_page, foreign_key: true, type: :uuid
      t.references :project, foreign_key: true, type: :uuid
      t.references :daily_log, foreign_key: true, type: :uuid
      t.boolean :favorite, null: false, default: false
      t.datetime :archived_at
      t.integer :ocr_status, null: false, default: 0
      t.integer :ai_status, null: false, default: 0
      t.integer :backup_status, null: false, default: 0
      t.integer :sync_status, null: false, default: 0
      t.string :client_draft_id
      t.datetime :last_synced_at
    end

    change_column_null :captures, :notebook_id, true
    add_index :captures, [:user_id, :favorite]
    add_index :captures, [:user_id, :archived_at]
    add_index :captures, [:user_id, :page_type]
    add_index :captures, [:user_id, :client_draft_id], unique: true

    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE captures
          SET
            page_type = COALESCE(
              (SELECT key FROM page_templates WHERE page_templates.id = captures.page_template_id),
              'blank'
            ),
            ocr_status = CASE
              WHEN status IN (0, 10, 20) THEN 1
              WHEN status = 30 THEN 2
              WHEN status = 40 THEN 3
              ELSE 0
            END,
            backup_status = 0,
            sync_status = 2
        SQL
      end
    end

    create_table :capture_revisions, id: :uuid do |t|
      t.references :capture, null: false, foreign_key: true, type: :uuid
      t.integer :revision_number, null: false
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :capture_revisions, [:capture_id, :revision_number], unique: true

    create_table :ai_summaries, id: :uuid do |t|
      t.references :capture, null: false, foreign_key: true, type: :uuid
      t.string :provider, null: false, default: "null"
      t.text :summary
      t.jsonb :bullets, null: false, default: []
      t.jsonb :tasks_extracted, null: false, default: []
      t.jsonb :entities, null: false, default: []
      t.jsonb :raw_payload, null: false, default: {}
      t.timestamps
    end

    create_table :attachments, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.references :capture, null: false, foreign_key: true, type: :uuid
      t.string :attachment_type, null: false
      t.string :title
      t.string :url
      t.string :content_type
      t.bigint :byte_size
      t.string :storage_key
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :attachments, [:capture_id, :attachment_type]

    create_table :tasks, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.references :capture, foreign_key: true, type: :uuid
      t.references :project, foreign_key: true, type: :uuid
      t.references :daily_log, foreign_key: true, type: :uuid
      t.string :title, null: false
      t.text :description
      t.boolean :completed, null: false, default: false
      t.integer :priority, null: false, default: 0
      t.date :due_date
      t.datetime :completed_at
      t.timestamps
    end

    add_index :tasks, [:user_id, :completed]
    add_index :tasks, [:user_id, :due_date]

    create_table :reference_links, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.references :source_capture, null: false, foreign_key: { to_table: :captures }, type: :uuid
      t.references :target_capture, null: false, foreign_key: { to_table: :captures }, type: :uuid
      t.string :relation_type, null: false, default: "related"
      t.timestamps
    end

    add_index :reference_links, [:source_capture_id, :target_capture_id], unique: true

    create_table :backup_records, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.references :capture, null: false, foreign_key: true, type: :uuid
      t.string :provider, null: false
      t.string :remote_file_id
      t.string :remote_path
      t.integer :status, null: false, default: 0
      t.datetime :last_attempt_at
      t.datetime :last_success_at
      t.text :error_message
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :backup_records, [:capture_id, :provider]
    add_index :backup_records, [:user_id, :status]

    create_table :app_settings, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid, index: { unique: true }
      t.string :ocr_mode, null: false, default: "manual"
      t.boolean :ai_enabled, null: false, default: false
      t.boolean :backup_enabled, null: false, default: false
      t.string :backup_provider
      t.jsonb :image_quality_preferences, null: false, default: {}
      t.jsonb :retention_rules, null: false, default: {}
      t.jsonb :privacy_options, null: false, default: {}
      t.timestamps
    end

    create_table :sync_jobs, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :syncable_type, null: false
      t.uuid :syncable_id, null: false
      t.string :job_type, null: false
      t.jsonb :payload, null: false, default: {}
      t.integer :status, null: false, default: 0
      t.integer :attempts, null: false, default: 0
      t.datetime :last_attempt_at
      t.text :error_message
      t.string :idempotency_key
      t.timestamps
    end

    add_index :sync_jobs, [:syncable_type, :syncable_id]
    add_index :sync_jobs, [:user_id, :status]
    add_index :sync_jobs, :idempotency_key, unique: true
  end
end
