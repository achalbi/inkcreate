class CreateInitialSchema < ActiveRecord::Migration[8.1]
  def up
    enable_extension "citext"
    enable_extension "pgcrypto"

    create_table :users, id: :uuid do |t|
      t.citext :email, null: false
      t.string :encrypted_password, null: false, default: ""
      t.string :reset_password_token
      t.datetime :reset_password_sent_at
      t.datetime :remember_created_at
      t.datetime :current_sign_in_at
      t.datetime :last_sign_in_at
      t.inet :current_sign_in_ip
      t.inet :last_sign_in_ip
      t.text :google_drive_access_token
      t.text :google_drive_refresh_token
      t.datetime :google_drive_token_expires_at
      t.string :google_drive_folder_id
      t.datetime :google_drive_connected_at
      t.string :time_zone, null: false, default: "UTC"
      t.string :locale, null: false, default: "en"
      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, :reset_password_token, unique: true

    create_table :notebooks, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :name, null: false
      t.string :slug, null: false
      t.string :color_token
      t.datetime :archived_at
      t.timestamps
    end

    add_index :notebooks, [:user_id, :slug], unique: true
    add_index :notebooks, [:user_id, :archived_at]

    create_table :page_templates, id: :uuid do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.text :description
      t.string :classifier_version, null: false, default: "v1"
      t.boolean :active, null: false, default: true
      t.jsonb :config, null: false, default: {}
      t.timestamps
    end

    add_index :page_templates, :key, unique: true

    create_table :captures, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.references :notebook, null: false, foreign_key: true, type: :uuid
      t.references :page_template, foreign_key: true, type: :uuid
      t.integer :status, null: false, default: 10
      t.integer :drive_sync_mode, null: false, default: 0
      t.string :title
      t.string :original_filename, null: false
      t.string :content_type, null: false
      t.bigint :byte_size, null: false
      t.string :checksum
      t.string :storage_bucket, null: false
      t.string :storage_object_key, null: false
      t.datetime :captured_at
      t.datetime :processed_at
      t.string :meeting_label
      t.string :conference_label
      t.string :project_label
      t.decimal :classification_confidence, precision: 5, scale: 4
      t.text :search_text
      t.tsvector :search_vector
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :captures, [:user_id, :created_at]
    add_index :captures, [:notebook_id, :captured_at]
    add_index :captures, :storage_object_key, unique: true
    add_index :captures, :search_vector, using: :gin

    create_table :ocr_jobs, id: :uuid do |t|
      t.references :capture, null: false, foreign_key: true, type: :uuid
      t.integer :status, null: false, default: 0
      t.string :provider, null: false, default: "tesseract"
      t.integer :attempts, null: false, default: 0
      t.string :correlation_id
      t.datetime :queued_at
      t.datetime :started_at
      t.datetime :finished_at
      t.text :error_message
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :ocr_jobs, [:capture_id, :created_at]
    add_index :ocr_jobs, :correlation_id

    create_table :ocr_results, id: :uuid do |t|
      t.references :capture, null: false, foreign_key: true, type: :uuid
      t.references :ocr_job, null: false, foreign_key: true, type: :uuid
      t.string :provider, null: false
      t.text :raw_text
      t.text :cleaned_text
      t.decimal :mean_confidence, precision: 5, scale: 4
      t.string :language, null: false, default: "eng"
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :ocr_results, [:capture_id, :created_at]

    create_table :drive_syncs, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.references :capture, null: false, foreign_key: true, type: :uuid
      t.integer :status, null: false, default: 0
      t.integer :mode, null: false, default: 0
      t.string :drive_folder_id, null: false
      t.string :image_file_id
      t.string :text_file_id
      t.datetime :last_attempted_at
      t.datetime :exported_at
      t.text :error_message
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :drive_syncs, [:capture_id, :created_at]
    add_index :drive_syncs, [:user_id, :status]

    create_table :tags, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.citext :name, null: false
      t.string :color_token
      t.timestamps
    end

    add_index :tags, [:user_id, :name], unique: true

    create_table :capture_tags, id: :uuid do |t|
      t.references :capture, null: false, foreign_key: true, type: :uuid
      t.references :tag, null: false, foreign_key: true, type: :uuid
      t.timestamps
    end

    add_index :capture_tags, [:capture_id, :tag_id], unique: true

    execute <<~SQL
      CREATE FUNCTION captures_search_vector_update() RETURNS trigger AS $$
      BEGIN
        NEW.search_vector :=
          setweight(to_tsvector('english', COALESCE(NEW.title, '')), 'A') ||
          setweight(to_tsvector('english', COALESCE(NEW.search_text, '')), 'B') ||
          setweight(to_tsvector('simple', COALESCE(NEW.meeting_label, '')), 'C') ||
          setweight(to_tsvector('simple', COALESCE(NEW.project_label, '')), 'C') ||
          setweight(to_tsvector('simple', COALESCE(NEW.conference_label, '')), 'C');
        RETURN NEW;
      END
      $$ LANGUAGE plpgsql;
    SQL

    execute <<~SQL
      CREATE TRIGGER captures_search_vector_before_write
      BEFORE INSERT OR UPDATE OF title, search_text, meeting_label, project_label, conference_label
      ON captures
      FOR EACH ROW
      EXECUTE FUNCTION captures_search_vector_update();
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS captures_search_vector_before_write ON captures"
    execute "DROP FUNCTION IF EXISTS captures_search_vector_update()"

    drop_table :capture_tags
    drop_table :tags
    drop_table :drive_syncs
    drop_table :ocr_results
    drop_table :ocr_jobs
    drop_table :captures
    drop_table :page_templates
    drop_table :notebooks
    drop_table :users
  end
end
