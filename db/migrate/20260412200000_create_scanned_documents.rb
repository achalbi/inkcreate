class CreateScannedDocuments < ActiveRecord::Migration[8.0]
  def change
    create_table :scanned_documents, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :user,           null: false, foreign_key: true, type: :uuid
      t.references :page,           null: true,  foreign_key: true, type: :uuid
      t.references :notepad_entry,  null: true,  foreign_key: true, type: :uuid

      t.string  :title
      t.text    :extracted_text
      t.string  :ocr_engine,        default: "tesseract"
      t.string  :ocr_language,      default: "eng"
      t.float   :ocr_confidence
      t.string  :enhancement_filter, default: "auto"
      t.text    :tags,               default: "[]"

      t.timestamps
    end
  end
end
