require "test_helper"

class DriveExportRecordTest < ActiveSupport::TestCase
  FakeRemoteFile = Struct.new(:id, :name, :parents, :content, :content_type, keyword_init: true)
  FakeFolder = Struct.new(:id, :name, keyword_init: true)
  EnsureFolderPathCall = Struct.new(:result, keyword_init: true) do
    def call
      result
    end
  end

  class FakeDriveService
    attr_reader :created_files, :updated_files, :deleted_file_ids

    def initialize
      @created_files = []
      @updated_files = []
      @deleted_file_ids = []
      @files = {}
      @sequence = 0
    end

    def create_file(metadata, upload_source: nil, content_type: nil, **)
      file = FakeRemoteFile.new(
        id: next_id,
        name: metadata.name,
        parents: Array(metadata.parents),
        content: read_upload_source(upload_source),
        content_type: content_type
      )
      @files[file.id] = file
      created_files << file
      OpenStruct.new(id: file.id, name: file.name, parents: file.parents)
    end

    def update_file(file_id, metadata, upload_source: nil, content_type: nil, add_parents: nil, remove_parents: nil, **)
      file = @files.fetch(file_id)
      file.name = metadata.name if metadata.respond_to?(:name) && metadata.name.present?
      if add_parents.present? || remove_parents.present?
        next_parents = Array(file.parents)
        next_parents -= Array(remove_parents)
        next_parents |= Array(add_parents)
        file.parents = next_parents
      elsif metadata.respond_to?(:parents) && metadata.parents.present?
        file.parents = Array(metadata.parents)
      end
      file.content = read_upload_source(upload_source) if upload_source
      file.content_type = content_type if content_type.present?
      updated_files << FakeRemoteFile.new(
        id: file.id,
        name: file.name,
        parents: file.parents,
        content: file.content,
        content_type: file.content_type
      )
      OpenStruct.new(id: file.id, name: file.name, parents: file.parents)
    end

    def get_file(file_id, **)
      file = @files.fetch(file_id)
      OpenStruct.new(id: file.id, name: file.name, parents: file.parents)
    end

    def delete_file(file_id)
      deleted_file_ids << file_id
      @files.delete(file_id)
    end

    def file_content_by_name(name)
      file = @files.values.reverse.find { |entry| entry.name == name }
      file&.content
    end

    def file_names
      @files.values.map(&:name)
    end

    private

    def next_id
      @sequence += 1
      "remote-file-#{@sequence}"
    end

    def read_upload_source(upload_source)
      return nil if upload_source.nil?
      return File.binread(upload_source) if upload_source.is_a?(String)

      if upload_source.respond_to?(:rewind) && upload_source.respond_to?(:read)
        upload_source.rewind
        return upload_source.read
      end

      if upload_source.respond_to?(:path)
        return File.binread(upload_source.path)
      end

      upload_source.to_s
    end
  end

  def build_user(email:)
    user = User.create!(
      email: email,
      password: "Password123!",
      password_confirmation: "Password123!",
      time_zone: "UTC",
      locale: "en",
      role: :user
    )
    user.update!(
      google_drive_connected_at: Time.current,
      google_drive_folder_id: "drive-root-folder"
    )
    user.define_singleton_method(:google_drive_connected?) { true }
    user.define_singleton_method(:google_drive_ready?) { true }
    user
  end

  test "exports notes, manifest, and related record assets into Drive" do
    user = build_user(email: "drive-export-record-assets@example.com")
    entry = user.notepad_entries.create!(
      entry_date: Date.new(2026, 4, 10),
      title: "",
      notes: "Meeting recap and follow-up items."
    )
    entry.photos.attach(image_attachment("meeting-board.jpg"))
    voice_note = entry.voice_notes.create!(
      audio: audio_attachment("check-in.m4a"),
      duration_seconds: 37,
      recorded_at: Time.zone.parse("2026-04-10 09:15:00"),
      byte_size: 16,
      mime_type: "audio/mp4",
      transcript: "Shared status update and next steps."
    )
    scanned_document = entry.scanned_documents.create!(
      user: user,
      title: "Receipt summary",
      enhancement_filter: "auto",
      ocr_engine: "tesseract",
      ocr_language: "eng",
      ocr_confidence: 92.5,
      enhanced_image: image_attachment("receipt-preview.jpg"),
      document_pdf: pdf_attachment("receipt.pdf"),
      extracted_text: "Total: 42.00\nVendor: Inkcreate Supplies"
    )
    scanned_document.tags_array = ["receipt", "travel"]
    scanned_document.save!

    todo_list = entry.create_todo_list!(enabled: true, hide_completed: true)
    todo_list.todo_items.create!(content: "Save receipt", position: 1, completed: false)
    reminded_item = todo_list.todo_items.create!(content: "Send expense report", position: 2, completed: true)
    reminded_item.create_reminder!(
      user: user,
      title: "Submit expense report",
      fire_at: Time.zone.parse("2026-04-11 10:00:00"),
      note: "Attach the scanned receipt."
    )

    export = GoogleDriveExport.create!(
      user: user,
      exportable: entry,
      status: :pending,
      remote_photo_file_ids: {}
    )
    drive_service = FakeDriveService.new

    with_drive_stubs(drive_service) do
      Drive::ExportRecord.new(google_drive_export: export).call
    end

    export.reload

    assert export.status_succeeded?
    assert_equal 1, export.remote_photo_file_ids.size
    assert_equal voice_note.id.to_s, export.metadata["remote_voice_note_audio_file_ids"].keys.first
    assert_equal scanned_document.id.to_s, export.metadata["remote_scanned_document_image_file_ids"].keys.first
    assert_equal scanned_document.id.to_s, export.metadata["remote_scanned_document_pdf_file_ids"].keys.first
    assert_equal scanned_document.id.to_s, export.metadata["remote_scanned_document_text_file_ids"].keys.first

    manifest = JSON.parse(drive_service.file_content_by_name("manifest.json"))

    assert_equal 1, manifest["voice_note_count"]
    assert_equal 1, manifest["photo_count"]
    assert_equal "Shared status update and next steps.", manifest["voice_notes"].first["transcript"]
    assert_equal 1, manifest["scanned_document_count"]
    assert_equal ["receipt", "travel"], manifest["scanned_documents"].first["tags"]
    assert_equal "Total: 42.00\nVendor: Inkcreate Supplies", manifest["scanned_documents"].first["extracted_text"]
    assert_equal true, manifest["todo_list"]["hide_completed"]
    assert_equal ["Save receipt", "Send expense report"], manifest["todo_list"]["items"].map { |item| item["content"] }
    assert_equal "Submit expense report", manifest["todo_list"]["items"].last["reminder"]["title"]

    notes_markdown = drive_service.file_content_by_name("notes.md")
    manifest_file = drive_service.created_files.find { |file| file.name == "manifest.json" }
    photo_file = drive_service.created_files.find { |file| file.name.end_with?("-meeting-board.jpg") }

    assert_includes notes_markdown, "## To-do list"
    assert_includes notes_markdown, "## Voice notes"
    assert_includes notes_markdown, "## Scanned documents"
    assert photo_file.present?
    refute_equal manifest_file.parents, photo_file.parents
    assert drive_service.file_names.any? { |name| name.start_with?("voice-note-#{voice_note.id}-") && name.end_with?(".m4a") }
    assert drive_service.file_names.any? { |name| name.end_with?("-preview.jpg") }
    assert drive_service.file_names.any? { |name| name.end_with?(".pdf") }
    assert drive_service.file_names.any? { |name| name.end_with?("-ocr.txt") }
  end

  test "re-export removes remote files for deleted voice notes and scanned documents" do
    user = build_user(email: "drive-export-record-cleanup@example.com")
    entry = user.notepad_entries.create!(
      entry_date: Date.new(2026, 4, 12),
      title: "",
      notes: "Cleanup test."
    )
    voice_note = entry.voice_notes.create!(
      audio: audio_attachment("cleanup.m4a"),
      duration_seconds: 21,
      recorded_at: Time.zone.parse("2026-04-12 08:30:00"),
      byte_size: 16,
      mime_type: "audio/mp4"
    )
    scanned_document = entry.scanned_documents.create!(
      user: user,
      title: "Cleanup scan",
      enhanced_image: image_attachment("cleanup-preview.jpg"),
      document_pdf: pdf_attachment("cleanup.pdf"),
      extracted_text: "Remove me"
    )
    export = GoogleDriveExport.create!(
      user: user,
      exportable: entry,
      status: :pending,
      remote_photo_file_ids: {}
    )
    drive_service = FakeDriveService.new

    with_drive_stubs(drive_service) do
      Drive::ExportRecord.new(google_drive_export: export).call

      remote_voice_file_id = export.reload.metadata["remote_voice_note_audio_file_ids"][voice_note.id.to_s]
      remote_preview_file_id = export.metadata["remote_scanned_document_image_file_ids"][scanned_document.id.to_s]
      remote_pdf_file_id = export.metadata["remote_scanned_document_pdf_file_ids"][scanned_document.id.to_s]
      remote_text_file_id = export.metadata["remote_scanned_document_text_file_ids"][scanned_document.id.to_s]

      voice_note.destroy!
      scanned_document.destroy!

      Drive::ExportRecord.new(google_drive_export: export).call

      assert_includes drive_service.deleted_file_ids, remote_voice_file_id
      assert_includes drive_service.deleted_file_ids, remote_preview_file_id
      assert_includes drive_service.deleted_file_ids, remote_pdf_file_id
      assert_includes drive_service.deleted_file_ids, remote_text_file_id
    end

    export.reload

    assert_equal({}, export.metadata["remote_voice_note_audio_file_ids"])
    assert_equal({}, export.metadata["remote_scanned_document_image_file_ids"])
    assert_equal({}, export.metadata["remote_scanned_document_pdf_file_ids"])
    assert_equal({}, export.metadata["remote_scanned_document_text_file_ids"])
  end

  test "re-export reuses existing ids and updates only changed remote files" do
    user = build_user(email: "drive-export-record-rerun@example.com")
    entry = user.notepad_entries.create!(
      entry_date: Date.new(2026, 4, 16),
      title: "",
      notes: "Initial notes."
    )
    entry.photos.attach(image_attachment("whiteboard.jpg"))
    voice_note = entry.voice_notes.create!(
      audio: audio_attachment("standup.m4a"),
      duration_seconds: 28,
      recorded_at: Time.zone.parse("2026-04-16 09:00:00"),
      byte_size: 16,
      mime_type: "audio/mp4",
      transcript: "Initial transcript."
    )
    scanned_document = entry.scanned_documents.create!(
      user: user,
      title: "Agenda",
      enhanced_image: image_attachment("agenda-preview.jpg"),
      document_pdf: pdf_attachment("agenda.pdf"),
      extracted_text: "Agenda v1"
    )
    export = GoogleDriveExport.create!(
      user: user,
      exportable: entry,
      status: :pending,
      remote_photo_file_ids: {}
    )
    drive_service = FakeDriveService.new

    with_drive_stubs(drive_service) do
      Drive::ExportRecord.new(google_drive_export: export).call
      export.reload

      original_created_file_ids = drive_service.created_files.map(&:id)
      original_notes_file_id = export.remote_notes_file_id
      original_manifest_file_id = export.remote_manifest_file_id
      original_photo_file_id = export.remote_photo_file_ids.values.first
      original_voice_file_id = export.metadata["remote_voice_note_audio_file_ids"][voice_note.id.to_s]
      original_preview_file_id = export.metadata["remote_scanned_document_image_file_ids"][scanned_document.id.to_s]
      original_pdf_file_id = export.metadata["remote_scanned_document_pdf_file_ids"][scanned_document.id.to_s]
      original_text_file_id = export.metadata["remote_scanned_document_text_file_ids"][scanned_document.id.to_s]

      entry.update_columns(notes: "Updated notes.", updated_at: Time.current + 1.second)
      voice_note.update_columns(transcript: "Updated transcript.", updated_at: Time.current + 1.second)
      scanned_document.update_columns(extracted_text: "Agenda v2", updated_at: Time.current + 1.second)
      export.update!(
        status: :pending,
        metadata: export.metadata.merge(
          Drive::RecordExportSections::PENDING_METADATA_KEY => Drive::RecordExportSections::ALL
        )
      )

      Drive::ExportRecord.new(google_drive_export: export).call
      export.reload

      assert_equal original_created_file_ids, drive_service.created_files.map(&:id)
      assert_equal original_notes_file_id, export.remote_notes_file_id
      assert_equal original_manifest_file_id, export.remote_manifest_file_id
      assert_equal original_photo_file_id, export.remote_photo_file_ids.values.first
      assert_equal original_voice_file_id, export.metadata["remote_voice_note_audio_file_ids"][voice_note.id.to_s]
      assert_equal original_preview_file_id, export.metadata["remote_scanned_document_image_file_ids"][scanned_document.id.to_s]
      assert_equal original_pdf_file_id, export.metadata["remote_scanned_document_pdf_file_ids"][scanned_document.id.to_s]
      assert_equal original_text_file_id, export.metadata["remote_scanned_document_text_file_ids"][scanned_document.id.to_s]

      updated_ids = drive_service.updated_files.map(&:id)

      assert_includes updated_ids, original_notes_file_id
      assert_includes updated_ids, original_manifest_file_id
      refute_includes updated_ids, original_photo_file_id
      refute_includes updated_ids, original_voice_file_id
      refute_includes updated_ids, original_preview_file_id
      refute_includes updated_ids, original_pdf_file_id
      assert_includes updated_ids, original_text_file_id
      assert_includes drive_service.file_content_by_name("notes.md"), "Updated notes."
      assert_equal "Updated transcript.", JSON.parse(drive_service.file_content_by_name("manifest.json"))["voice_notes"].first["transcript"]
      assert_equal "Agenda v2", JSON.parse(drive_service.file_content_by_name("manifest.json"))["scanned_documents"].first["extracted_text"]
    end
  end

  test "adding a photo does not rewrite existing photo files" do
    user = build_user(email: "drive-export-record-photo-siblings@example.com")
    entry = user.notepad_entries.create!(
      entry_date: Date.new(2026, 4, 16),
      title: "",
      notes: "Photo sync."
    )
    entry.photos.attach(image_attachment("first-board.jpg"))
    export = GoogleDriveExport.create!(
      user: user,
      exportable: entry,
      status: :pending,
      remote_photo_file_ids: {},
      metadata: { Drive::RecordExportSections::PENDING_METADATA_KEY => Drive::RecordExportSections::ALL }
    )
    drive_service = FakeDriveService.new

    with_drive_stubs(drive_service) do
      Drive::ExportRecord.new(google_drive_export: export).call
      export.reload

      original_created_count = drive_service.created_files.size
      original_photo_file_id = export.remote_photo_file_ids.values.first

      drive_service.updated_files.clear
      entry.photos.attach(image_attachment("second-board.jpg"))
      export.update!(
        status: :pending,
        metadata: export.metadata.merge(
          Drive::RecordExportSections::PENDING_METADATA_KEY => [Drive::RecordExportSections::PHOTOS]
        )
      )

      Drive::ExportRecord.new(google_drive_export: export).call
      export.reload

      assert_equal 2, export.remote_photo_file_ids.size
      assert_equal original_created_count + 1, drive_service.created_files.size
      refute_includes drive_service.updated_files.map(&:id), original_photo_file_id
      assert drive_service.file_names.any? { |name| name.end_with?("-first-board.jpg") }
      assert drive_service.file_names.any? { |name| name.end_with?("-second-board.jpg") }
    end
  end

  test "adding a voice note does not rewrite existing audio files and exports audio mp4 as m4a" do
    user = build_user(email: "drive-export-record-voice-siblings@example.com")
    entry = user.notepad_entries.create!(
      entry_date: Date.new(2026, 4, 16),
      title: "",
      notes: "Voice sync."
    )
    first_voice_note = entry.voice_notes.create!(
      audio: audio_attachment("first-recording.mp4"),
      duration_seconds: 21,
      recorded_at: Time.zone.parse("2026-04-16 09:00:00"),
      byte_size: 16,
      mime_type: "audio/mp4"
    )
    export = GoogleDriveExport.create!(
      user: user,
      exportable: entry,
      status: :pending,
      remote_photo_file_ids: {},
      metadata: { Drive::RecordExportSections::PENDING_METADATA_KEY => Drive::RecordExportSections::ALL }
    )
    drive_service = FakeDriveService.new

    with_drive_stubs(drive_service) do
      Drive::ExportRecord.new(google_drive_export: export).call
      export.reload

      original_created_count = drive_service.created_files.size
      original_voice_file_id = export.metadata["remote_voice_note_audio_file_ids"][first_voice_note.id.to_s]
      assert drive_service.file_names.any? { |name| name.start_with?("voice-note-#{first_voice_note.id}-") && name.end_with?(".m4a") }

      drive_service.updated_files.clear
      entry.voice_notes.create!(
        audio: audio_attachment("second-recording.mp4"),
        duration_seconds: 18,
        recorded_at: Time.zone.parse("2026-04-16 09:05:00"),
        byte_size: 16,
        mime_type: "audio/mp4"
      )
      export.update!(
        status: :pending,
        metadata: export.metadata.merge(
          Drive::RecordExportSections::PENDING_METADATA_KEY => [Drive::RecordExportSections::VOICE_NOTES]
        )
      )

      Drive::ExportRecord.new(google_drive_export: export).call
      export.reload

      assert_equal 2, export.metadata["remote_voice_note_audio_file_ids"].size
      assert_equal original_created_count + 1, drive_service.created_files.size
      refute_includes drive_service.updated_files.map(&:id), original_voice_file_id
    end
  end

  test "targeted record export only updates notes and manifest files" do
    user = build_user(email: "drive-export-record-targeted@example.com")
    entry = user.notepad_entries.create!(
      entry_date: Date.new(2026, 4, 16),
      title: "",
      notes: "Initial notes."
    )
    entry.photos.attach(image_attachment("plan.jpg"))
    voice_note = entry.voice_notes.create!(
      audio: audio_attachment("plan.m4a"),
      duration_seconds: 18,
      recorded_at: Time.zone.parse("2026-04-16 09:05:00"),
      byte_size: 16,
      mime_type: "audio/mp4",
      transcript: "Initial transcript."
    )
    scanned_document = entry.scanned_documents.create!(
      user: user,
      title: "Plan scan",
      enhanced_image: image_attachment("plan-preview.jpg"),
      document_pdf: pdf_attachment("plan.pdf"),
      extracted_text: "Plan v1"
    )
    export = GoogleDriveExport.create!(
      user: user,
      exportable: entry,
      status: :pending,
      remote_photo_file_ids: {},
      metadata: { Drive::RecordExportSections::PENDING_METADATA_KEY => Drive::RecordExportSections::ALL }
    )
    drive_service = FakeDriveService.new

    with_drive_stubs(drive_service) do
      Drive::ExportRecord.new(google_drive_export: export).call
      export.reload

      drive_service.updated_files.clear
      created_count = drive_service.created_files.size
      photo_file_id = export.remote_photo_file_ids.values.first
      voice_file_id = export.metadata["remote_voice_note_audio_file_ids"][voice_note.id.to_s]
      preview_file_id = export.metadata["remote_scanned_document_image_file_ids"][scanned_document.id.to_s]
      pdf_file_id = export.metadata["remote_scanned_document_pdf_file_ids"][scanned_document.id.to_s]
      text_file_id = export.metadata["remote_scanned_document_text_file_ids"][scanned_document.id.to_s]

      entry.update_columns(notes: "Notes only update.", updated_at: Time.current + 1.second)
      export.update!(
        status: :pending,
        metadata: export.metadata.merge(
          Drive::RecordExportSections::PENDING_METADATA_KEY => [Drive::RecordExportSections::RECORD]
        )
      )

      Drive::ExportRecord.new(google_drive_export: export).call
      export.reload

      updated_ids = drive_service.updated_files.map(&:id)

      assert_equal created_count, drive_service.created_files.size
      assert_includes updated_ids, export.remote_notes_file_id
      assert_includes updated_ids, export.remote_manifest_file_id
      refute_includes updated_ids, photo_file_id
      refute_includes updated_ids, voice_file_id
      refute_includes updated_ids, preview_file_id
      refute_includes updated_ids, pdf_file_id
      refute_includes updated_ids, text_file_id
    end
  end

  test "targeted photo export only updates photo files and manifest" do
    user = build_user(email: "drive-export-record-photo-targeted@example.com")
    entry = user.notepad_entries.create!(
      entry_date: Date.new(2026, 4, 16),
      title: "",
      notes: "Initial notes."
    )
    export = GoogleDriveExport.create!(
      user: user,
      exportable: entry,
      status: :pending,
      remote_photo_file_ids: {},
      metadata: { Drive::RecordExportSections::PENDING_METADATA_KEY => Drive::RecordExportSections::ALL }
    )
    drive_service = FakeDriveService.new

    with_drive_stubs(drive_service) do
      Drive::ExportRecord.new(google_drive_export: export).call
      export.reload

      drive_service.updated_files.clear
      original_notes_file_id = export.remote_notes_file_id
      original_manifest_file_id = export.remote_manifest_file_id
      original_created_count = drive_service.created_files.size

      entry.photos.attach(image_attachment("board.jpg"))
      export.update!(
        status: :pending,
        metadata: export.metadata.merge(
          Drive::RecordExportSections::PENDING_METADATA_KEY => [Drive::RecordExportSections::PHOTOS]
        )
      )

      Drive::ExportRecord.new(google_drive_export: export).call
      export.reload

      updated_ids = drive_service.updated_files.map(&:id)

      assert_includes updated_ids, original_manifest_file_id
      refute_includes updated_ids, original_notes_file_id
      assert_equal original_created_count + 1, drive_service.created_files.size
      assert_equal 1, export.remote_photo_file_ids.size
    end
  end

  test "omits binary media files when media backups are disabled but still exports structured text data" do
    user = build_user(email: "drive-export-record-privacy@example.com")
    user.ensure_app_setting!.update!(privacy_options: { "include_photos_in_backups" => false })

    entry = user.notepad_entries.create!(
      entry_date: Date.new(2026, 4, 14),
      title: "",
      notes: "Privacy-aware export."
    )
    entry.voice_notes.create!(
      audio: audio_attachment("privacy.m4a"),
      duration_seconds: 12,
      recorded_at: Time.zone.parse("2026-04-14 07:45:00"),
      byte_size: 16,
      mime_type: "audio/mp4",
      transcript: "Transcript stays in the manifest."
    )
    entry.scanned_documents.create!(
      user: user,
      title: "Privacy scan",
      enhanced_image: image_attachment("privacy-preview.jpg"),
      document_pdf: pdf_attachment("privacy.pdf"),
      extracted_text: "OCR text still exports."
    )
    export = GoogleDriveExport.create!(
      user: user,
      exportable: entry,
      status: :pending,
      remote_photo_file_ids: {}
    )
    drive_service = FakeDriveService.new

    with_drive_stubs(drive_service) do
      Drive::ExportRecord.new(google_drive_export: export).call
    end

    export.reload
    manifest = JSON.parse(drive_service.file_content_by_name("manifest.json"))

    assert_equal false, manifest["voice_note_audio_exported"]
    assert_equal false, manifest["scanned_document_files_exported"]
    assert_equal "Transcript stays in the manifest.", manifest["voice_notes"].first["transcript"]
    assert_equal "OCR text still exports.", manifest["scanned_documents"].first["extracted_text"]
    assert_equal({}, export.metadata["remote_voice_note_audio_file_ids"])
    assert_equal({}, export.metadata["remote_scanned_document_image_file_ids"])
    assert_equal({}, export.metadata["remote_scanned_document_pdf_file_ids"])
    assert export.metadata["remote_scanned_document_text_file_ids"].values.any?
    assert drive_service.file_names.none? { |name| name.start_with?("voice-note-") }
    assert drive_service.file_names.none? { |name| name.end_with?("-preview.jpg") }
    assert drive_service.file_names.none? { |name| name == "privacy.pdf" }
    assert drive_service.file_names.any? { |name| name.end_with?("-ocr.txt") }
  end

  private

  def with_drive_stubs(drive_service)
    folders = {}
    ensure_folder_path = lambda do |parent_id:, segments:, **|
      key = [parent_id, *segments].join("/")
      folder = folders[key] ||= FakeFolder.new(id: "folder-#{folders.size + 1}", name: segments.last)
      EnsureFolderPathCall.new(result: folder)
    end

    with_instance_override(User, :google_drive_connected?, -> { true }) do
      with_instance_override(User, :google_drive_ready?, -> { true }) do
        Drive::ClientFactory.stub(:build, drive_service) do
          Drive::EnsureFolderPath.stub(:new, ensure_folder_path) do
            yield
          end
        end
      end
    end
  end

  def with_instance_override(klass, method_name, implementation)
    backup_method = :"__codex_backup_#{method_name}_#{Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)}"
    had_original = klass.method_defined?(method_name) || klass.private_method_defined?(method_name)

    klass.alias_method backup_method, method_name if had_original
    klass.define_method(method_name, implementation)

    yield
  ensure
    klass.remove_method(method_name) if klass.method_defined?(method_name) || klass.private_method_defined?(method_name)

    if had_original
      klass.alias_method method_name, backup_method
      klass.remove_method(backup_method)
    end
  end

  def audio_attachment(filename, content_type: "audio/mp4")
    {
      io: StringIO.new("audio-bytes"),
      filename: filename,
      content_type: content_type
    }
  end

  def image_attachment(filename)
    {
      io: StringIO.new("jpeg-bytes"),
      filename: filename,
      content_type: "image/jpeg"
    }
  end

  def pdf_attachment(filename)
    {
      io: StringIO.new("%PDF-1.4\n1 0 obj\n<<>>\nendobj\ntrailer\n<<>>\n%%EOF\n"),
      filename: filename,
      content_type: "application/pdf"
    }
  end
end
