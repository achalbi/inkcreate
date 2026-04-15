require "test_helper"

unless defined?(Google::Cloud::Storage)
  module Google
    module Cloud
      class Storage
      end
    end
  end
end

class DriveExportCaptureTest < ActiveSupport::TestCase
  FakeRemoteFile = Struct.new(:id, :name, :parents, :content, :content_type, :mime_type, keyword_init: true)
  FakeFolder = Struct.new(:id, :name, keyword_init: true)
  EnsureFolderPathCall = Struct.new(:result, keyword_init: true) do
    def call
      result
    end
  end

  class FakeDriveService
    FOLDER_MIME_TYPE = "application/vnd.google-apps.folder".freeze

    attr_reader :created_files, :updated_files, :deleted_file_ids

    def initialize
      @created_files = []
      @updated_files = []
      @deleted_file_ids = []
      @files = {}
      @folders_by_key = {}
      @sequence = 0
    end

    def ensure_folder_path(parent_id:, segments:)
      current_parent_id = parent_id
      last_folder = nil

      Array(segments).each do |segment|
        key = [current_parent_id, segment].join("/")
        last_folder = @folders_by_key[key]
        unless last_folder
          last_folder = FakeRemoteFile.new(
            id: next_id,
            name: segment,
            parents: [current_parent_id],
            mime_type: FOLDER_MIME_TYPE
          )
          @folders_by_key[key] = last_folder
          @files[last_folder.id] = last_folder
        end

        current_parent_id = last_folder.id
      end

      FakeFolder.new(id: last_folder.id, name: last_folder.name)
    end

    def create_file(metadata, upload_source: nil, content_type: nil, **)
      file = FakeRemoteFile.new(
        id: next_id,
        name: metadata.name,
        parents: Array(metadata.parents),
        content: read_upload_source(upload_source),
        content_type: content_type,
        mime_type: metadata.respond_to?(:mime_type) ? metadata.mime_type : nil
      )
      @files[file.id] = file
      created_files << duplicate(file)
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
      updated_files << duplicate(file)
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
      file = @files.values.reverse.find { |entry| entry.name == name && entry.mime_type != FOLDER_MIME_TYPE }
      file&.content
    end

    def file_names
      @files.values.reject { |file| file.mime_type == FOLDER_MIME_TYPE }.map(&:name)
    end

    private

    def next_id
      @sequence += 1
      "remote-file-#{@sequence}"
    end

    def duplicate(file)
      FakeRemoteFile.new(
        id: file.id,
        name: file.name,
        parents: Array(file.parents),
        content: file.content,
        content_type: file.content_type,
        mime_type: file.mime_type
      )
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

  class FakeStorageClient
    def initialize(file_map:)
      @file_map = file_map.stringify_keys
    end

    def bucket(name)
      FakeStorageBucket.new(files: @file_map.fetch(name))
    end
  end

  class FakeStorageBucket
    def initialize(files:)
      @files = files.stringify_keys
    end

    def file(key)
      FakeStorageFile.new(content: @files.fetch(key))
    end
  end

  class FakeStorageFile
    def initialize(content:)
      @content = content
    end

    def download(path)
      File.binwrite(path, @content)
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
    user
  end

  test "exports a full capture package with manifest, OCR, attachments, tasks, revisions, and links" do
    user = build_user(email: "drive-export-capture-package@example.com")
    project = user.projects.create!(title: "Operations")
    daily_log = user.daily_logs.create!(entry_date: Date.new(2026, 4, 15), title: "April 15")
    physical_page = user.physical_pages.create!(page_number: 12, template_type: "blank", label: "Meeting pad")
    page_template = PageTemplate.find_or_create_by!(key: "blank") do |template|
      template.name = "Blank"
      template.description = "Blank page"
    end

    capture = user.captures.create!(
      title: "Quarterly kickoff",
      description: "Initial planning capture.",
      original_filename: "capture.jpg",
      content_type: "image/jpeg",
      byte_size: 13,
      storage_bucket: "capture-bucket",
      storage_object_key: "captures/quarterly-kickoff.jpg",
      page_type: "blank",
      project: project,
      daily_log: daily_log,
      physical_page: physical_page,
      page_template: page_template,
      captured_at: Time.zone.parse("2026-04-15 09:30:00"),
      metadata: { "source" => "ios" }
    )
    capture.tags << user.tags.create!(name: "planning")
    capture.tags << user.tags.create!(name: "meeting")

    capture.capture_revisions.create!(
      revision_number: 1,
      metadata: { "snapshot" => { "title" => "Draft kickoff" } }
    )

    ocr_job = capture.ocr_jobs.create!(provider: "tesseract", status: :succeeded)
    capture.ocr_results.create!(
      ocr_job: ocr_job,
      provider: "tesseract",
      cleaned_text: "Agenda\nBudget review",
      raw_text: "Agenda Budget review",
      mean_confidence: 0.91,
      language: "eng",
      metadata: { "pages" => 1 }
    )

    capture.ai_summaries.create!(
      provider: "openai",
      summary: "Budget and staffing were the primary themes.",
      bullets: ["Budget review", "Hiring plan"],
      tasks_extracted: [{ "title" => "Send recap" }],
      entities: [{ "label" => "Budget", "type" => "topic" }],
      raw_payload: { "model" => "gpt-5.4-mini" }
    )

    uploaded_attachment = capture.attachments.new(
      user: user,
      attachment_type: "file",
      title: "Budget sheet",
      metadata: { "source" => "upload" }
    )
    uploaded_attachment.asset.attach(
      io: StringIO.new("spreadsheet-bytes"),
      filename: "budget.csv",
      content_type: "text/csv"
    )
    uploaded_attachment.content_type = "text/csv"
    uploaded_attachment.byte_size = 17
    uploaded_attachment.save!

    capture.attachments.create!(
      user: user,
      attachment_type: "url",
      title: "Planning doc",
      url: "https://example.com/planning"
    )

    task = capture.tasks.create!(
      user: user,
      title: "Send kickoff recap",
      description: "Share notes and owners.",
      priority: :high,
      severity: :major,
      due_date: Date.new(2026, 4, 16),
      reminder_at: Time.zone.parse("2026-04-15 17:00:00"),
      reminder_recurrence: "weekly"
    )
    task.tags_array = ["follow-up"]
    task.save!
    task.task_subtasks.create!(title: "Attach budget sheet", position: 1, completed: false)

    related_capture = user.captures.create!(
      title: "Follow-up capture",
      original_filename: "follow-up.jpg",
      content_type: "image/jpeg",
      byte_size: 10,
      storage_bucket: "capture-bucket",
      storage_object_key: "captures/follow-up.jpg",
      page_type: "blank"
    )
    capture.outgoing_reference_links.create!(user: user, target_capture: related_capture, relation_type: "related")
    related_capture.outgoing_reference_links.create!(user: user, target_capture: capture, relation_type: "depends_on")

    backup_record = capture.backup_records.create!(
      user: user,
      provider: "google_drive",
      status: :pending,
      remote_path: user.google_drive_folder_id,
      metadata: { "requested_at" => Time.current.iso8601 }
    )
    drive_sync = capture.drive_syncs.create!(
      user: user,
      drive_folder_id: user.google_drive_folder_id,
      mode: :manual,
      status: :pending,
      metadata: { "backup_record_id" => backup_record.id }
    )
    drive_service = FakeDriveService.new

    with_capture_drive_stubs(drive_service, storage_files: {
      "capture-bucket" => {
        "captures/quarterly-kickoff.jpg" => "image-bytes",
        "captures/follow-up.jpg" => "follow-up-bytes"
      }
    }) do
      Drive::ExportCapture.new(drive_sync: drive_sync).call
    end

    drive_sync.reload
    backup_record.reload

    assert drive_sync.status_succeeded?
    assert_equal drive_sync.metadata["remote_folder_id"], backup_record.remote_file_id
    assert_equal "Captures / #{Drive::ExportLayout.record_folder_name(capture)}", backup_record.remote_path
    assert_equal uploaded_attachment.id.to_s, drive_sync.metadata["remote_attachment_file_ids"].keys.first
    assert_includes drive_service.file_names, "Quarterly kickoff.jpg"
    assert_includes drive_service.file_names, "manifest.json"
    assert_includes drive_service.file_names, "latest-ocr.txt"
    assert drive_service.file_names.any? { |name| name.start_with?("attachment-01-budget-sheet") }

    manifest = JSON.parse(drive_service.file_content_by_name("manifest.json"))

    assert_equal "capture", manifest["package_type"]
    assert_equal "Quarterly kickoff", manifest["capture"]["title"]
    assert_equal ["meeting", "planning"], manifest["capture"]["tags"]
    assert_equal "Agenda\nBudget review", manifest["latest_ocr_result"]["cleaned_text"]
    assert_equal 1, manifest["ocr_results"].size
    assert_equal "Budget and staffing were the primary themes.", manifest["latest_ai_summary"]["summary"]
    assert_equal 2, manifest["attachments"].size
    assert_equal true, manifest["attachments"].first["stored_file"]
    assert_equal "Send kickoff recap", manifest["tasks"].first["title"]
    assert_equal "Attach budget sheet", manifest["tasks"].first["subtasks"].first["title"]
    assert_equal 1, manifest["revisions"].size
    assert_equal "related", manifest["reference_links"]["outgoing"].first["relation_type"]
    assert_equal "depends_on", manifest["reference_links"]["incoming"].first["relation_type"]
  end

  test "repeat capture exports reuse the same package folder and clean up removed OCR and attachment files" do
    user = build_user(email: "drive-export-capture-rerun@example.com")
    capture = user.captures.create!(
      title: "Original capture",
      original_filename: "capture.jpg",
      content_type: "image/jpeg",
      byte_size: 11,
      storage_bucket: "capture-bucket",
      storage_object_key: "captures/original.jpg",
      page_type: "blank"
    )
    ocr_job = capture.ocr_jobs.create!(provider: "tesseract", status: :succeeded)
    capture.ocr_results.create!(
      ocr_job: ocr_job,
      provider: "tesseract",
      cleaned_text: "Original OCR text",
      raw_text: "Original OCR text"
    )
    attachment = capture.attachments.new(user: user, attachment_type: "file", title: "Original sheet")
    attachment.asset.attach(
      io: StringIO.new("attachment-bytes"),
      filename: "sheet.csv",
      content_type: "text/csv"
    )
    attachment.content_type = "text/csv"
    attachment.byte_size = 16
    attachment.save!

    initial_sync = capture.drive_syncs.create!(
      user: user,
      drive_folder_id: user.google_drive_folder_id,
      mode: :manual,
      status: :pending
    )
    drive_service = FakeDriveService.new

    with_capture_drive_stubs(drive_service, storage_files: {
      "capture-bucket" => { "captures/original.jpg" => "image-bytes" }
    }) do
      Drive::ExportCapture.new(drive_sync: initial_sync).call

      initial_sync.reload
      folder_id = initial_sync.metadata["remote_folder_id"]
      manifest_file_id = initial_sync.metadata["remote_manifest_file_id"]
      attachment_file_id = initial_sync.metadata["remote_attachment_file_ids"][attachment.id.to_s]
      text_file_id = initial_sync.text_file_id

      capture.update!(title: "Renamed capture")
      capture.ocr_results.destroy_all
      attachment.destroy!

      rerun_sync = capture.drive_syncs.create!(
        user: user,
        drive_folder_id: user.google_drive_folder_id,
        mode: :manual,
        status: :pending
      )

      Drive::ExportCapture.new(drive_sync: rerun_sync).call

      rerun_sync.reload

      assert_equal folder_id, rerun_sync.metadata["remote_folder_id"]
      assert_equal manifest_file_id, rerun_sync.metadata["remote_manifest_file_id"]
      assert_equal initial_sync.image_file_id, rerun_sync.image_file_id
      assert_nil rerun_sync.text_file_id
      assert_equal({}, rerun_sync.metadata["remote_attachment_file_ids"])
      assert_includes drive_service.deleted_file_ids, attachment_file_id
      assert_includes drive_service.deleted_file_ids, text_file_id
      assert drive_service.updated_files.any? { |file| file.id == folder_id && file.name == Drive::ExportLayout.record_folder_name(capture) }

      manifest = JSON.parse(drive_service.file_content_by_name("manifest.json"))

      assert_equal "Renamed capture", manifest["capture"]["title"]
      assert_nil manifest["latest_ocr_result"]
      assert_equal [], manifest["attachments"]
    end
  end

  private

  def with_capture_drive_stubs(drive_service, storage_files:)
    ensure_folder_path = lambda do |parent_id:, segments:, **|
      EnsureFolderPathCall.new(result: drive_service.ensure_folder_path(parent_id: parent_id, segments: segments))
    end

    with_instance_override(User, :google_drive_connected?, -> { true }) do
      Drive::ClientFactory.stub(:build, drive_service) do
        Drive::EnsureFolderPath.stub(:new, ensure_folder_path) do
          Google::Cloud::Storage.stub(:new, FakeStorageClient.new(file_map: storage_files)) do
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
end
