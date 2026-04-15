# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_04_16_100000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "citext"
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "active_storage_attachments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.uuid "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "ai_summaries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.jsonb "bullets", default: [], null: false
    t.uuid "capture_id", null: false
    t.datetime "created_at", null: false
    t.jsonb "entities", default: [], null: false
    t.string "provider", default: "null", null: false
    t.jsonb "raw_payload", default: {}, null: false
    t.text "summary"
    t.jsonb "tasks_extracted", default: [], null: false
    t.datetime "updated_at", null: false
    t.index ["capture_id"], name: "index_ai_summaries_on_capture_id"
  end

  create_table "app_settings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "ai_enabled", default: false, null: false
    t.boolean "backup_enabled", default: true, null: false
    t.string "backup_provider"
    t.datetime "created_at", null: false
    t.jsonb "image_quality_preferences", default: {}, null: false
    t.string "ocr_mode", default: "manual", null: false
    t.jsonb "privacy_options", default: {}, null: false
    t.jsonb "retention_rules", default: {}, null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["user_id"], name: "index_app_settings_on_user_id", unique: true
  end

  create_table "attachments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "attachment_type", null: false
    t.bigint "byte_size"
    t.uuid "capture_id", null: false
    t.string "content_type"
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "storage_key"
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "url"
    t.uuid "user_id", null: false
    t.index ["capture_id", "attachment_type"], name: "index_attachments_on_capture_id_and_attachment_type"
    t.index ["capture_id"], name: "index_attachments_on_capture_id"
    t.index ["user_id"], name: "index_attachments_on_user_id"
  end

  create_table "backup_records", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "capture_id", null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "last_attempt_at"
    t.datetime "last_success_at"
    t.jsonb "metadata", default: {}, null: false
    t.string "provider", null: false
    t.string "remote_file_id"
    t.string "remote_path"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["capture_id", "provider"], name: "index_backup_records_on_capture_id_and_provider"
    t.index ["capture_id"], name: "index_backup_records_on_capture_id"
    t.index ["user_id", "status"], name: "index_backup_records_on_user_id_and_status"
    t.index ["user_id"], name: "index_backup_records_on_user_id"
  end

  create_table "capture_revisions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "capture_id", null: false
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.integer "revision_number", null: false
    t.datetime "updated_at", null: false
    t.index ["capture_id", "revision_number"], name: "index_capture_revisions_on_capture_id_and_revision_number", unique: true
    t.index ["capture_id"], name: "index_capture_revisions_on_capture_id"
  end

  create_table "capture_tags", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "capture_id", null: false
    t.datetime "created_at", null: false
    t.uuid "tag_id", null: false
    t.datetime "updated_at", null: false
    t.index ["capture_id", "tag_id"], name: "index_capture_tags_on_capture_id_and_tag_id", unique: true
    t.index ["capture_id"], name: "index_capture_tags_on_capture_id"
    t.index ["tag_id"], name: "index_capture_tags_on_tag_id"
  end

  create_table "captures", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "ai_status", default: 0, null: false
    t.datetime "archived_at"
    t.integer "backup_status", default: 0, null: false
    t.bigint "byte_size", null: false
    t.datetime "captured_at"
    t.string "checksum"
    t.decimal "classification_confidence", precision: 5, scale: 4
    t.string "client_draft_id"
    t.string "conference_label"
    t.string "content_type", null: false
    t.datetime "created_at", null: false
    t.uuid "daily_log_id"
    t.text "description"
    t.integer "drive_sync_mode", default: 0, null: false
    t.boolean "favorite", default: false, null: false
    t.datetime "last_synced_at"
    t.string "meeting_label"
    t.jsonb "metadata", default: {}, null: false
    t.uuid "notebook_id"
    t.integer "ocr_status", default: 0, null: false
    t.string "original_filename", null: false
    t.uuid "page_template_id"
    t.string "page_type"
    t.uuid "physical_page_id"
    t.datetime "processed_at"
    t.uuid "project_id"
    t.string "project_label"
    t.text "search_text"
    t.tsvector "search_vector"
    t.integer "status", default: 10, null: false
    t.string "storage_bucket", null: false
    t.string "storage_object_key", null: false
    t.integer "sync_status", default: 0, null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["daily_log_id"], name: "index_captures_on_daily_log_id"
    t.index ["notebook_id", "captured_at"], name: "index_captures_on_notebook_id_and_captured_at"
    t.index ["notebook_id"], name: "index_captures_on_notebook_id"
    t.index ["page_template_id"], name: "index_captures_on_page_template_id"
    t.index ["physical_page_id"], name: "index_captures_on_physical_page_id"
    t.index ["project_id"], name: "index_captures_on_project_id"
    t.index ["search_vector"], name: "index_captures_on_search_vector", using: :gin
    t.index ["storage_object_key"], name: "index_captures_on_storage_object_key", unique: true
    t.index ["user_id", "archived_at"], name: "index_captures_on_user_id_and_archived_at"
    t.index ["user_id", "client_draft_id"], name: "index_captures_on_user_id_and_client_draft_id", unique: true
    t.index ["user_id", "created_at"], name: "index_captures_on_user_id_and_created_at"
    t.index ["user_id", "favorite"], name: "index_captures_on_user_id_and_favorite"
    t.index ["user_id", "page_type"], name: "index_captures_on_user_id_and_page_type"
    t.index ["user_id"], name: "index_captures_on_user_id"
  end

  create_table "chapters", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.text "description"
    t.uuid "notebook_id", null: false
    t.integer "position", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["notebook_id", "deleted_at"], name: "index_chapters_on_notebook_id_and_deleted_at"
    t.index ["notebook_id", "position"], name: "index_chapters_on_notebook_id_and_position"
    t.index ["notebook_id"], name: "index_chapters_on_notebook_id"
  end

  create_table "daily_logs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "entry_date", null: false
    t.jsonb "metadata", default: {}, null: false
    t.text "quick_note"
    t.text "summary"
    t.string "title"
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["user_id", "entry_date"], name: "index_daily_logs_on_user_id_and_entry_date", unique: true
    t.index ["user_id"], name: "index_daily_logs_on_user_id"
  end

  create_table "devices", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "label"
    t.datetime "last_seen_at"
    t.string "push_auth_key"
    t.boolean "push_enabled", default: false, null: false
    t.text "push_endpoint"
    t.string "push_p256dh_key"
    t.datetime "updated_at", null: false
    t.string "user_agent", default: "", null: false
    t.uuid "user_id", null: false
    t.index ["push_endpoint"], name: "index_devices_on_push_endpoint", unique: true, where: "(push_endpoint IS NOT NULL)"
    t.index ["user_id", "push_enabled"], name: "index_devices_on_user_id_and_push_enabled"
    t.index ["user_id"], name: "index_devices_on_user_id"
  end

  create_table "drive_syncs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "capture_id", null: false
    t.datetime "created_at", null: false
    t.string "drive_folder_id", null: false
    t.text "error_message"
    t.datetime "exported_at"
    t.string "image_file_id"
    t.datetime "last_attempted_at"
    t.jsonb "metadata", default: {}, null: false
    t.integer "mode", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.string "text_file_id"
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["capture_id", "created_at"], name: "index_drive_syncs_on_capture_id_and_created_at"
    t.index ["capture_id"], name: "index_drive_syncs_on_capture_id"
    t.index ["user_id", "status"], name: "index_drive_syncs_on_user_id_and_status"
    t.index ["user_id"], name: "index_drive_syncs_on_user_id"
  end

  create_table "google_drive_exports", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "drive_folder_id"
    t.text "error_message"
    t.uuid "exportable_id", null: false
    t.string "exportable_type", null: false
    t.datetime "exported_at"
    t.datetime "last_attempted_at"
    t.jsonb "metadata", default: {}, null: false
    t.string "remote_folder_id"
    t.string "remote_manifest_file_id"
    t.string "remote_notes_file_id"
    t.jsonb "remote_photo_file_ids", default: {}, null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["exportable_type", "exportable_id"], name: "idx_on_exportable_type_exportable_id_06996d1409", unique: true
    t.index ["exportable_type", "exportable_id"], name: "index_google_drive_exports_on_exportable"
    t.index ["user_id", "status"], name: "index_google_drive_exports_on_user_id_and_status"
    t.index ["user_id"], name: "index_google_drive_exports_on_user_id"
  end

  create_table "notebooks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "archived_at"
    t.string "color_token"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.string "slug", null: false
    t.integer "status", default: 0, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["user_id", "archived_at"], name: "index_notebooks_on_user_id_and_archived_at"
    t.index ["user_id", "slug"], name: "index_notebooks_on_user_id_and_slug", unique: true
    t.index ["user_id", "status"], name: "index_notebooks_on_user_id_and_status"
    t.index ["user_id"], name: "index_notebooks_on_user_id"
  end

  create_table "notepad_entries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "entry_date", null: false
    t.text "notes"
    t.string "title"
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["user_id", "entry_date"], name: "index_notepad_entries_on_user_id_and_entry_date"
    t.index ["user_id"], name: "index_notepad_entries_on_user_id"
  end

  create_table "ocr_jobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "attempts", default: 0, null: false
    t.uuid "capture_id", null: false
    t.string "correlation_id"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "finished_at"
    t.jsonb "metadata", default: {}, null: false
    t.string "provider", default: "tesseract", null: false
    t.datetime "queued_at"
    t.datetime "started_at"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["capture_id", "created_at"], name: "index_ocr_jobs_on_capture_id_and_created_at"
    t.index ["capture_id"], name: "index_ocr_jobs_on_capture_id"
    t.index ["correlation_id"], name: "index_ocr_jobs_on_correlation_id"
  end

  create_table "ocr_results", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "capture_id", null: false
    t.text "cleaned_text"
    t.datetime "created_at", null: false
    t.string "language", default: "eng", null: false
    t.decimal "mean_confidence", precision: 5, scale: 4
    t.jsonb "metadata", default: {}, null: false
    t.uuid "ocr_job_id", null: false
    t.string "provider", null: false
    t.text "raw_text"
    t.datetime "updated_at", null: false
    t.index ["capture_id", "created_at"], name: "index_ocr_results_on_capture_id_and_created_at"
    t.index ["capture_id"], name: "index_ocr_results_on_capture_id"
    t.index ["ocr_job_id"], name: "index_ocr_results_on_ocr_job_id"
  end

  create_table "page_templates", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "classifier_version", default: "v1", null: false
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_page_templates_on_key", unique: true
  end

  create_table "pages", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.date "captured_on"
    t.uuid "chapter_id", null: false
    t.datetime "created_at", null: false
    t.text "notes"
    t.integer "position", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["chapter_id", "position"], name: "index_pages_on_chapter_id_and_position"
    t.index ["chapter_id"], name: "index_pages_on_chapter_id"
  end

  create_table "physical_pages", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "label"
    t.text "notes"
    t.integer "page_number", null: false
    t.string "template_type", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["user_id", "page_number"], name: "index_physical_pages_on_user_id_and_page_number", unique: true
    t.index ["user_id"], name: "index_physical_pages_on_user_id"
  end

  create_table "projects", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "archived_at"
    t.string "color", default: "#17392d", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "slug", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["user_id", "archived_at"], name: "index_projects_on_user_id_and_archived_at"
    t.index ["user_id", "slug"], name: "index_projects_on_user_id_and_slug", unique: true
    t.index ["user_id"], name: "index_projects_on_user_id"
  end

  create_table "reference_links", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "relation_type", default: "related", null: false
    t.uuid "source_capture_id", null: false
    t.uuid "target_capture_id", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["source_capture_id", "target_capture_id"], name: "idx_on_source_capture_id_target_capture_id_89ee04f0ef", unique: true
    t.index ["source_capture_id"], name: "index_reference_links_on_source_capture_id"
    t.index ["target_capture_id"], name: "index_reference_links_on_target_capture_id"
    t.index ["user_id"], name: "index_reference_links_on_user_id"
  end

  create_table "reminders", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "fire_at", null: false
    t.datetime "last_triggered_at"
    t.text "note"
    t.datetime "snooze_until"
    t.integer "status", default: 0, null: false
    t.uuid "target_id"
    t.string "target_type"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["status", "fire_at"], name: "index_reminders_on_status_and_fire_at"
    t.index ["target_type", "target_id"], name: "index_reminders_on_target"
    t.index ["user_id", "status", "fire_at"], name: "index_reminders_on_user_id_and_status_and_fire_at"
    t.index ["user_id"], name: "index_reminders_on_user_id"
  end

  create_table "scanned_documents", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "enhancement_filter", default: "auto"
    t.text "extracted_text"
    t.uuid "notepad_entry_id"
    t.float "ocr_confidence"
    t.string "ocr_engine", default: "tesseract"
    t.string "ocr_language", default: "eng"
    t.uuid "page_id"
    t.text "tags", default: "[]"
    t.string "title"
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["notepad_entry_id"], name: "index_scanned_documents_on_notepad_entry_id"
    t.index ["page_id"], name: "index_scanned_documents_on_page_id"
    t.index ["user_id"], name: "index_scanned_documents_on_user_id"
  end

  create_table "sync_jobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "attempts", default: 0, null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "idempotency_key"
    t.string "job_type", null: false
    t.datetime "last_attempt_at"
    t.jsonb "payload", default: {}, null: false
    t.integer "status", default: 0, null: false
    t.uuid "syncable_id", null: false
    t.string "syncable_type", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["idempotency_key"], name: "index_sync_jobs_on_idempotency_key", unique: true
    t.index ["syncable_type", "syncable_id"], name: "index_sync_jobs_on_syncable_type_and_syncable_id"
    t.index ["user_id", "status"], name: "index_sync_jobs_on_user_id_and_status"
    t.index ["user_id"], name: "index_sync_jobs_on_user_id"
  end

  create_table "tags", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "color_token"
    t.datetime "created_at", null: false
    t.citext "name", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["user_id", "name"], name: "index_tags_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_tags_on_user_id"
  end

  create_table "task_subtasks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "completed", default: false, null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "position", default: 0, null: false
    t.uuid "task_id", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["task_id", "position"], name: "index_task_subtasks_on_task_id_and_position"
    t.index ["task_id"], name: "index_task_subtasks_on_task_id"
  end

  create_table "tasks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "capture_id"
    t.boolean "completed", default: false, null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.uuid "daily_log_id"
    t.text "description"
    t.date "due_date"
    t.string "link_chapter_id"
    t.string "link_label"
    t.string "link_notebook_id"
    t.string "link_page_id"
    t.string "link_resource_id"
    t.string "link_type"
    t.integer "priority", default: 0, null: false
    t.uuid "project_id"
    t.datetime "reminder_at"
    t.string "reminder_recurrence", default: "none", null: false
    t.integer "severity", default: 0, null: false
    t.text "tags", default: "[]", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["capture_id"], name: "index_tasks_on_capture_id"
    t.index ["daily_log_id"], name: "index_tasks_on_daily_log_id"
    t.index ["project_id"], name: "index_tasks_on_project_id"
    t.index ["user_id", "completed"], name: "index_tasks_on_user_id_and_completed"
    t.index ["user_id", "due_date"], name: "index_tasks_on_user_id_and_due_date"
    t.index ["user_id"], name: "index_tasks_on_user_id"
  end

  create_table "todo_items", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "completed", default: false, null: false
    t.datetime "completed_at"
    t.string "content", null: false
    t.datetime "created_at", null: false
    t.integer "position", default: 1, null: false
    t.uuid "todo_list_id", null: false
    t.datetime "updated_at", null: false
    t.index ["todo_list_id", "position"], name: "index_todo_items_on_todo_list_id_and_position"
    t.index ["todo_list_id"], name: "index_todo_items_on_todo_list_id"
  end

  create_table "todo_lists", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.boolean "hide_completed", default: false, null: false
    t.boolean "manually_reordered", default: false, null: false
    t.uuid "notepad_entry_id"
    t.uuid "page_id"
    t.datetime "updated_at", null: false
    t.index ["notepad_entry_id"], name: "index_todo_lists_on_notepad_entry_id", unique: true, where: "(notepad_entry_id IS NOT NULL)"
    t.index ["page_id"], name: "index_todo_lists_on_page_id", unique: true
    t.check_constraint "(\nCASE\n    WHEN page_id IS NOT NULL THEN 1\n    ELSE 0\nEND +\nCASE\n    WHEN notepad_entry_id IS NOT NULL THEN 1\n    ELSE 0\nEND) = 1", name: "todo_lists_exactly_one_owner"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "current_sign_in_at"
    t.inet "current_sign_in_ip"
    t.citext "email", null: false
    t.string "encrypted_password", default: "", null: false
    t.text "google_drive_access_token"
    t.datetime "google_drive_connected_at"
    t.string "google_drive_folder_id"
    t.text "google_drive_refresh_token"
    t.datetime "google_drive_token_expires_at"
    t.datetime "last_sign_in_at"
    t.inet "last_sign_in_ip"
    t.string "locale", default: "en", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "role", default: 0, null: false
    t.string "time_zone", default: "UTC", null: false
    t.boolean "time_zone_locked", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["role"], name: "index_users_on_role"
  end

  create_table "voice_notes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.bigint "byte_size", default: 0, null: false
    t.datetime "created_at", null: false
    t.integer "duration_seconds", default: 0, null: false
    t.string "mime_type", null: false
    t.uuid "notepad_entry_id"
    t.uuid "page_id"
    t.datetime "recorded_at", null: false
    t.text "transcript"
    t.datetime "updated_at", null: false
    t.index ["notepad_entry_id", "recorded_at"], name: "index_voice_notes_on_notepad_entry_id_and_recorded_at"
    t.index ["notepad_entry_id"], name: "index_voice_notes_on_notepad_entry_id"
    t.index ["page_id", "recorded_at"], name: "index_voice_notes_on_page_id_and_recorded_at"
    t.index ["page_id"], name: "index_voice_notes_on_page_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "ai_summaries", "captures"
  add_foreign_key "app_settings", "users"
  add_foreign_key "attachments", "captures"
  add_foreign_key "attachments", "users"
  add_foreign_key "backup_records", "captures"
  add_foreign_key "backup_records", "users"
  add_foreign_key "capture_revisions", "captures"
  add_foreign_key "capture_tags", "captures"
  add_foreign_key "capture_tags", "tags"
  add_foreign_key "captures", "daily_logs"
  add_foreign_key "captures", "notebooks"
  add_foreign_key "captures", "page_templates"
  add_foreign_key "captures", "physical_pages"
  add_foreign_key "captures", "projects"
  add_foreign_key "captures", "users"
  add_foreign_key "chapters", "notebooks"
  add_foreign_key "daily_logs", "users"
  add_foreign_key "devices", "users"
  add_foreign_key "drive_syncs", "captures"
  add_foreign_key "drive_syncs", "users"
  add_foreign_key "google_drive_exports", "users"
  add_foreign_key "notebooks", "users"
  add_foreign_key "notepad_entries", "users"
  add_foreign_key "ocr_jobs", "captures"
  add_foreign_key "ocr_results", "captures"
  add_foreign_key "ocr_results", "ocr_jobs"
  add_foreign_key "pages", "chapters"
  add_foreign_key "physical_pages", "users"
  add_foreign_key "projects", "users"
  add_foreign_key "reference_links", "captures", column: "source_capture_id"
  add_foreign_key "reference_links", "captures", column: "target_capture_id"
  add_foreign_key "reference_links", "users"
  add_foreign_key "reminders", "users"
  add_foreign_key "scanned_documents", "notepad_entries"
  add_foreign_key "scanned_documents", "pages"
  add_foreign_key "scanned_documents", "users"
  add_foreign_key "sync_jobs", "users"
  add_foreign_key "tags", "users"
  add_foreign_key "task_subtasks", "tasks"
  add_foreign_key "tasks", "captures"
  add_foreign_key "tasks", "daily_logs"
  add_foreign_key "tasks", "projects"
  add_foreign_key "tasks", "users"
  add_foreign_key "todo_items", "todo_lists"
  add_foreign_key "todo_lists", "notepad_entries"
  add_foreign_key "todo_lists", "pages"
  add_foreign_key "voice_notes", "notepad_entries"
  add_foreign_key "voice_notes", "pages"
end
