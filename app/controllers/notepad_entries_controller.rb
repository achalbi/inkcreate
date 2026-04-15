class NotepadEntriesController < BrowserController
  GALLERY_ITEMS_PER_PAGE = 9
  include ScannedDocumentSupport
  include DriveRecordExportScheduling

  before_action :require_authenticated_user!
  before_action :set_notepad_entry, only: %i[show edit update destroy destroy_photo]
  before_action :load_move_destination_groups, only: %i[show edit update]

  def index
    @view_mode = index_view_mode
    @selected_entry_date = selected_entry_date
    entries = current_user.notepad_entries.with_attached_photos.recent_first
    entries = entries.includes(todo_list: :todo_items) if TodoList.schema_ready? && TodoItem.schema_ready?
    entries = entries.where(entry_date: @selected_entry_date) if @selected_entry_date.present?
    @entries_by_date = entries.group_by(&:entry_date)
    prepare_gallery(entries)
  end

  def show; end

  def new
    @notepad_entry = current_user.notepad_entries.new(entry_date: Time.zone.today)
    @notepad_entry.title = @notepad_entry.display_title
  end

  def quick_create
    entry_date = selected_entry_date || Time.zone.today
    @notepad_entry = current_user.notepad_entries.new(entry_date: entry_date, title: "")
    @notepad_entry.allow_blank_content = true

    if @notepad_entry.save
      redirect_to edit_notepad_entry_path(@notepad_entry), notice: "Daily page created."
    else
      redirect_to notepad_entries_path(date: entry_date.iso8601, view: index_view_mode), alert: @notepad_entry.errors.full_messages.to_sentence
    end
  end

  def create
    @notepad_entry = current_user.notepad_entries.new(notepad_entry_attributes)
    preserve_pending_photos(@notepad_entry, notepad_entry_params)
    assign_pending_content_from_params(@notepad_entry, notepad_entry_params, raw_notepad_entry_attributes)

    if @notepad_entry.save
      with_deferred_drive_record_export(@notepad_entry) do
        attach_pending_photos(@notepad_entry)
        persist_pending_voice_notes(@notepad_entry)
        persist_pending_todo_list(@notepad_entry, notepad_entry_params)
        persist_pending_scanned_documents(@notepad_entry, payloads: @notepad_entry.pending_scanned_document_payloads, user: current_user)
        @notepad_entry.pending_scanned_document_payloads = []
      end
      redirect_to create_redirect_path(@notepad_entry), notice: create_notice_message
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    return quick_update_notepad_entry if quick_edit_request?

    preserve_pending_photos(@notepad_entry, notepad_entry_params)
    assign_pending_content_from_params(@notepad_entry, notepad_entry_params, raw_notepad_entry_attributes)
    @notepad_entry.allow_blank_content = allow_blank_content_for_update?(notes_value: notepad_entry_attributes[:notes])

    if moving_to_notebook_chapter?
      @notepad_entry.assign_attributes(notepad_entry_attributes)
      return move_notepad_entry_to_chapter
    end

    if @notepad_entry.update(notepad_entry_attributes)
      with_deferred_drive_record_export(@notepad_entry) do
        attach_pending_photos(@notepad_entry)
        persist_pending_voice_notes(@notepad_entry)
        persist_pending_todo_list(@notepad_entry, notepad_entry_params)
        persist_pending_scanned_documents(@notepad_entry, payloads: @notepad_entry.pending_scanned_document_payloads, user: current_user)
        @notepad_entry.pending_scanned_document_payloads = []
      end
      redirect_to notepad_entry_path(@notepad_entry), notice: "Notepad entry updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @notepad_entry.destroy!
    redirect_to notepad_entries_path, notice: "Notepad entry deleted."
  end

  def destroy_photo
    attachment = @notepad_entry.photos.attachments.find(params[:attachment_id])
    attachment.purge
    schedule_drive_export(@notepad_entry)
    redirect_back fallback_location: notepad_entry_path(@notepad_entry), notice: "Photo removed."
  end

  private

  def set_notepad_entry
    scope = current_user.notepad_entries.with_attached_photos
    includes = notepad_entry_detail_includes
    scope = scope.includes(*includes) if includes.any?
    @notepad_entry = scope.find(params[:id])
  end

  def load_move_destination_groups
    @move_destination_notebooks = current_user.notebooks.includes(chapters: :pages).ordered.select do |notebook|
      notebook.chapters.any?
    end
    @selected_move_destination_chapter_id = move_destination_chapter_id
    @selected_move_destination_label = move_destination_label(move_destination_chapter)
  end

  def notepad_entry_params
    params.require(:notepad_entry).permit(
      :title,
      :notes,
      :entry_date,
      :todo_list_enabled,
      :todo_list_hide_completed,
      :pending_scanned_documents_json,
      retained_photo_signed_ids: [],
      photos: [],
      voice_note_uploads: [],
      voice_note_duration_seconds: [],
      voice_note_recorded_ats: [],
      todo_item_contents: []
    )
  end

  def notepad_entry_attributes
    notepad_entry_params.except(
      :photos,
      :retained_photo_signed_ids,
      :voice_note_uploads,
      :voice_note_duration_seconds,
      :voice_note_recorded_ats,
      :todo_list_enabled,
      :todo_list_hide_completed,
      :todo_item_contents,
      :pending_scanned_documents_json
    )
  end

  def preserve_pending_photos(entry, attrs)
    entry.retained_photo_signed_ids = retained_photo_signed_ids(attrs) + uploaded_photo_signed_ids(attrs[:photos])
  end

  def retained_photo_signed_ids(attrs)
    Array(attrs[:retained_photo_signed_ids]).reject(&:blank?)
  end

  def uploaded_photo_signed_ids(files)
    Array(files).reject(&:blank?).filter_map do |upload|
      next unless upload.respond_to?(:open)

      ActiveStorage::Blob.create_and_upload!(
        io: upload.open,
        filename: upload.original_filename,
        content_type: upload.content_type
      ).signed_id
    end
  end

  def attach_pending_photos(entry)
    signed_ids = entry.retained_photo_signed_ids
    return if signed_ids.empty?

    entry.photos.attach(signed_ids)
    entry.retained_photo_signed_ids = []
  end

  def raw_notepad_entry_attributes
    params.fetch(:notepad_entry, {})
  end

  def assign_pending_content_from_params(entry, attrs, raw_attrs)
    entry.pending_voice_note_uploads = raw_voice_note_uploads(raw_attrs)
    entry.pending_voice_note_duration_seconds = Array(attrs[:voice_note_duration_seconds])
    entry.pending_voice_note_recorded_ats = Array(attrs[:voice_note_recorded_ats])
    entry.pending_todo_list_enabled = attrs[:todo_list_enabled]
    entry.pending_todo_list_hide_completed = attrs[:todo_list_hide_completed]
    entry.pending_todo_item_contents = Array(attrs[:todo_item_contents])
    entry.pending_scanned_document_payloads = parse_pending_scanned_document_payloads(attrs[:pending_scanned_documents_json])
  end

  def raw_voice_note_uploads(raw_attrs)
    Array(raw_attrs[:voice_note_uploads]).filter_map do |upload|
      next if upload.blank?
      next upload if upload.respond_to?(:content_type)

      nil
    end
  end

  def persist_pending_voice_notes(entry)
    return unless VoiceNote.notepad_entries_supported?

    uploads = entry.pending_voice_note_uploads
    return if uploads.empty?

    uploads.each_with_index do |upload, index|
      next unless upload.respond_to?(:content_type)

      voice_note = entry.voice_notes.new(
        duration_seconds: normalized_voice_note_duration(entry, index),
        recorded_at: normalized_voice_note_recorded_at(entry, index),
        byte_size: upload.size,
        mime_type: upload.content_type.to_s
      )
      voice_note.audio.attach(upload)
      voice_note.save!
    end

    entry.pending_voice_note_uploads = []
  end

  def persist_pending_todo_list(entry, attrs)
    return unless TodoList.schema_ready? && TodoItem.schema_ready?

    item_contents = Array(attrs[:todo_item_contents]).filter_map { |content| content.to_s.squish.presence }
    should_enable = ActiveModel::Type::Boolean.new.cast(attrs[:todo_list_enabled]) || item_contents.any?
    should_hide_completed = ActiveModel::Type::Boolean.new.cast(attrs[:todo_list_hide_completed]) == true
    return unless should_enable || entry.todo_list.present?

    todo_list = entry.todo_list || entry.build_todo_list
    todo_list.enabled = should_enable
    todo_list.hide_completed = should_hide_completed
    todo_list.save! if todo_list.new_record? || todo_list.changed?

    item_contents.each do |content|
      todo_list.todo_items.create!(content: content)
    end

    entry.pending_todo_item_contents = []
  end

  def normalized_voice_note_duration(entry, index)
    entry.pending_voice_note_duration_seconds[index].to_i.clamp(0, VoiceNote::MAX_DURATION_SECONDS)
  end

  def normalized_voice_note_recorded_at(entry, index)
    Time.zone.parse(entry.pending_voice_note_recorded_ats[index].to_s)
  rescue ArgumentError, TypeError
    Time.current
  end

  def quick_edit_request?
    params[:quick_edit_modal].to_s == "1"
  end

  def quick_update_notepad_entry
    @notepad_entry.allow_blank_content = allow_blank_content_for_update?(notes_value: notepad_entry_params[:notes])

    if @notepad_entry.update(notepad_entry_params.slice(:title, :notes))
      schedule_drive_export(@notepad_entry)
      redirect_to notepad_entry_path(@notepad_entry), notice: "Notepad entry updated."
    else
      @show_quick_edit_modal = true
      render :show, status: :unprocessable_entity
    end
  end

  def moving_to_notebook_chapter?
    params[:intent].to_s == "move_to_notebook"
  end

  def move_destination_chapter_id
    params[:move_to_chapter_id].presence
  end

  def move_destination_chapter
    return if move_destination_chapter_id.blank?

    Chapter.kept
      .joins(:notebook)
      .where(notebooks: { user_id: current_user.id })
      .find_by(id: move_destination_chapter_id)
  end

  def move_notepad_entry_to_chapter
    chapter = move_destination_chapter

    unless chapter
      @notepad_entry.errors.add(:base, "Choose a notebook chapter to move this page into.")
      return render :edit, status: :unprocessable_entity
    end

    page = chapter.pages.new(
      title: @notepad_entry.title,
      notes: @notepad_entry.notes,
      captured_on: @notepad_entry.entry_date
    )
    page.retained_photo_signed_ids = photo_signed_ids_for_move
    assign_pending_page_content_for_move(page)

    with_deferred_drive_record_export(page) do
      NotepadEntry.transaction do
        page.save!
        attach_pending_photos(page)
        move_pending_voice_notes_to_page(page)
        move_voice_notes_to_page(page)
        move_todo_list_to_page(page)
        persist_pending_scanned_documents(page, payloads: @notepad_entry.pending_scanned_document_payloads, user: current_user)
        move_scanned_documents_to_page(page)
        reset_moved_associations!(@notepad_entry, :voice_notes, :todo_list, :scanned_documents)
        @notepad_entry.photos.detach
        @notepad_entry.destroy!
      end
    end
    redirect_to notebook_chapter_page_path(chapter.notebook, chapter, page),
      notice: "Daily page moved to #{chapter.notebook.title} / #{chapter.title}."
  rescue ActiveRecord::RecordInvalid
    page.errors.full_messages.each do |message|
      @notepad_entry.errors.add(:base, message)
    end

    render :edit, status: :unprocessable_entity
  end

  def photo_signed_ids_for_move
    (@notepad_entry.photos.blobs.map(&:signed_id) + @notepad_entry.retained_photo_signed_ids).uniq
  end

  def move_voice_notes_to_page(page)
    return unless VoiceNote.notepad_entries_supported?

    @notepad_entry.voice_notes.find_each do |voice_note|
      voice_note.update!(page: page, notepad_entry: nil)
    end
  end

  def move_pending_voice_notes_to_page(page)
    return unless VoiceNote.notepad_entries_supported?

    @notepad_entry.pending_voice_note_uploads.each_with_index do |upload, index|
      next unless upload.respond_to?(:content_type)

      voice_note = page.voice_notes.new(
        duration_seconds: normalized_voice_note_duration(@notepad_entry, index),
        recorded_at: normalized_voice_note_recorded_at(@notepad_entry, index),
        byte_size: upload.size,
        mime_type: upload.content_type.to_s
      )
      voice_note.audio.attach(upload)
      voice_note.save!
    end
  end

  def assign_pending_page_content_for_move(page)
    page.pending_voice_note_uploads = Array(@notepad_entry.pending_voice_note_uploads)
    page.pending_voice_note_uploads += [Object.new] if VoiceNote.notepad_entries_supported? && @notepad_entry.voice_notes.exists?
    page.pending_scanned_document_payloads = Array(@notepad_entry.pending_scanned_document_payloads)
    page.pending_existing_scanned_document_count = @notepad_entry.scanned_documents.count

    todo_state = pending_todo_move_state
    page.pending_todo_list_enabled = todo_state[:enabled]
    page.pending_todo_list_hide_completed = todo_state[:hide_completed]
    page.pending_todo_item_contents = todo_state[:validation_item_contents]
  end

  def move_todo_list_to_page(page)
    return unless TodoList.schema_ready? && TodoItem.schema_ready?

    source_list = @notepad_entry.todo_list
    todo_state = pending_todo_move_state(source_list)
    return unless source_list.present? || todo_state[:enabled] || todo_state[:pending_item_contents].any?

    target_list = page.todo_list || page.build_todo_list
    target_list.enabled = todo_state[:enabled]
    target_list.hide_completed = todo_state[:hide_completed]
    target_list.save! if target_list.new_record? || target_list.changed?

    if source_list.present?
      source_list.todo_items.update_all(todo_list_id: target_list.id, updated_at: Time.current)
      source_list.destroy!
    end

    todo_state[:pending_item_contents].each do |content|
      target_list.todo_items.create!(content: content)
    end
  end

  def move_scanned_documents_to_page(page)
    @notepad_entry.scanned_documents.find_each do |scanned_document|
      scanned_document.update!(page: page, notepad_entry: nil)
    end
  end

  def reset_moved_associations!(record, *association_names)
    association_names.each do |association_name|
      record.association(association_name).reset
    end
  end

  def pending_todo_move_state(source_list = @notepad_entry.todo_list)
    pending_item_contents = @notepad_entry.pending_todo_item_contents
    enabled = todo_state_value_from_params(:todo_list_enabled) { source_list&.enabled? } || pending_item_contents.any?
    hide_completed = todo_state_value_from_params(:todo_list_hide_completed) { source_list&.hide_completed? } == true

    validation_item_contents = pending_item_contents.dup
    if enabled && source_list.present?
      validation_item_contents = source_list.display_todo_items.pluck(:content) + validation_item_contents
    end

    {
      enabled: enabled,
      hide_completed: hide_completed,
      pending_item_contents: pending_item_contents,
      validation_item_contents: validation_item_contents
    }
  end

  def todo_state_value_from_params(key)
    raw_attrs = raw_notepad_entry_attributes
    return ActiveModel::Type::Boolean.new.cast(raw_attrs[key]) if raw_attrs.key?(key)
    return ActiveModel::Type::Boolean.new.cast(raw_attrs[key.to_s]) if raw_attrs.key?(key.to_s)

    yield
  end

  def move_destination_label(chapter)
    return if chapter.blank?

    "#{chapter.notebook.title} > #{chapter.title}"
  end

  def allow_blank_content_for_update?(notes_value:)
    blank_notepad_entry_shell? &&
      notes_value.to_s.blank? &&
      @notepad_entry.retained_photo_signed_ids.empty? &&
      @notepad_entry.pending_voice_note_uploads.empty? &&
      @notepad_entry.pending_scanned_document_payloads.empty? &&
      @notepad_entry.pending_todo_item_contents.empty?
  end

  def blank_notepad_entry_shell?
    @notepad_entry.notes.to_s.blank? &&
      !@notepad_entry.photos.attached? &&
      !@notepad_entry.voice_notes.exists? &&
      !@notepad_entry.scanned_documents.exists? &&
      !@notepad_entry.todo_items.exists?
  end

  def create_redirect_path(entry)
    return edit_notepad_entry_path(entry) if redirect_to_edit_after_create?

    notepad_entry_path(entry)
  end

  def create_notice_message
    return "Daily page created. You can add notes, photos, or more voice notes now." if redirect_to_edit_after_create?

    "Notepad entry created."
  end

  def redirect_to_edit_after_create?
    params[:after_create].to_s == "edit"
  end

  def notepad_entry_detail_includes
    includes = []
    includes << { voice_notes: [audio_attachment: :blob] } if VoiceNote.notepad_entries_supported?

    if TodoList.schema_ready? && TodoItem.schema_ready?
      includes << if Reminder.schema_ready?
        { todo_list: { todo_items: :reminder } }
      else
        { todo_list: :todo_items }
      end
    end

    includes
  end

  def index_view_mode
    params[:view] == "gallery" ? "gallery" : "list"
  end

  def prepare_gallery(entries)
    @gallery_query = params[:q].to_s.strip

    gallery_entries = filter_gallery_entries(entries, @gallery_query)
    all_photo_gallery_items = build_photo_gallery_items(gallery_entries)

    @gallery_total_count = all_photo_gallery_items.size
    @gallery_page = bounded_gallery_page(@gallery_total_count)
    @gallery_total_pages = [(@gallery_total_count.to_f / GALLERY_ITEMS_PER_PAGE).ceil, 1].max

    offset = (@gallery_page - 1) * GALLERY_ITEMS_PER_PAGE
    @photo_gallery_items = all_photo_gallery_items.slice(offset, GALLERY_ITEMS_PER_PAGE) || []
    @gallery_first_item_number = @gallery_total_count.zero? ? 0 : offset + 1
    @gallery_last_item_number = @gallery_total_count.zero? ? 0 : [offset + @photo_gallery_items.size, @gallery_total_count].min
  end

  def filter_gallery_entries(entries, query)
    return entries if query.blank?

    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"

    entries.where(
      "notepad_entries.title ILIKE :pattern OR notepad_entries.notes ILIKE :pattern OR CAST(notepad_entries.entry_date AS text) ILIKE :pattern",
      pattern: pattern
    )
  end

  def build_photo_gallery_items(entries)
    entries.flat_map do |entry|
      entry.photos.attachments.map do |photo|
        { entry: entry, photo: photo }
      end
    end.sort_by { |item| item[:photo].created_at }.reverse
  end

  def bounded_gallery_page(total_count)
    requested_page = params[:page].to_i
    requested_page = 1 if requested_page < 1

    total_pages = [((total_count.to_f / GALLERY_ITEMS_PER_PAGE).ceil), 1].max
    [requested_page, total_pages].min
  end

  def selected_entry_date
    return if params[:date].blank?

    Date.iso8601(params[:date])
  rescue ArgumentError
    nil
  end
end
