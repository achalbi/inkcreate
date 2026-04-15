class PagesController < BrowserController
  include ScannedDocumentSupport

  before_action :require_authenticated_user!
  before_action :set_notebook
  before_action :set_chapter
  before_action :set_page, only: %i[show edit update destroy move destroy_photo]
  before_action :load_move_destination_groups, only: %i[show update]

  def show; end

  def new
    @page = @chapter.pages.new(captured_on: Time.zone.today)
    @page.title = @page.display_title
  end

  def create
    @page = @chapter.pages.new(page_attributes)
    preserve_pending_photos(@page, page_params)
    assign_pending_content_from_params(@page, page_params, raw_page_attributes)

    if @page.save
      attach_pending_photos(@page)
      persist_pending_voice_notes(@page)
      persist_pending_todo_list(@page, page_params)
      persist_pending_scanned_documents(@page, payloads: @page.pending_scanned_document_payloads, user: current_user)
      @page.pending_scanned_document_payloads = []
      schedule_drive_export(@page)
      redirect_to notebook_chapter_page_path(@notebook, @chapter, @page), notice: "Page created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if moving_to_notebook_chapter?
      return move_page_to_chapter
    end

    preserve_pending_photos(@page, page_params)
    assign_pending_content_from_params(@page, page_params, raw_page_attributes)

    if @page.update(page_attributes)
      attach_pending_photos(@page)
      persist_pending_voice_notes(@page)
      persist_pending_todo_list(@page, page_params)
      persist_pending_scanned_documents(@page, payloads: @page.pending_scanned_document_payloads, user: current_user)
      @page.pending_scanned_document_payloads = []
      schedule_drive_export(@page)
      redirect_to notebook_chapter_page_path(@notebook, @chapter, @page), notice: "Page updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @page.destroy!
    redirect_to notebook_chapter_path(@notebook, @chapter), notice: "Page deleted."
  end

  def move
    move_within_scope(@chapter.pages.ordered, @page, params[:direction])
    redirect_to notebook_chapter_path(@notebook, @chapter), notice: "Page order updated."
  end

  def destroy_photo
    attachment = @page.photos.attachments.find(params[:attachment_id])
    attachment.purge
    schedule_drive_export(@page)
    redirect_back fallback_location: notebook_chapter_page_path(@notebook, @chapter, @page), notice: "Photo removed."
  end

  private

  def set_notebook
    @notebook = current_user.notebooks.find(params[:notebook_id])
  end

  def set_chapter
    @chapter = @notebook.all_chapters.find(params[:chapter_id])
  end

  def set_page
    scope = @chapter.pages.with_attached_photos
    includes = page_detail_includes
    scope = scope.includes(*includes) if includes.any?
    @page = scope.find(params[:id])
  end

  def page_params
    params.require(:page).permit(
      :title,
      :notes,
      :captured_on,
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

  def page_attributes
    page_params.except(
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

  def load_move_destination_groups
    @move_destination_notebooks = current_user.notebooks.includes(chapters: :pages).ordered.filter_map do |notebook|
      eligible_chapters = notebook.chapters.reject { |candidate| candidate.id == @page.chapter_id }
      next if eligible_chapters.empty?

      notebook.tap do |destination_notebook|
        destination_notebook.define_singleton_method(:chapters) { eligible_chapters }
      end
    end

    @selected_move_destination_chapter_id = move_destination_chapter_id
    @selected_move_destination_label = move_destination_label(move_destination_chapter)
  end

  def preserve_pending_photos(page, attrs)
    page.retained_photo_signed_ids = retained_photo_signed_ids(attrs) + uploaded_photo_signed_ids(attrs[:photos])
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

  def attach_pending_photos(page)
    signed_ids = page.retained_photo_signed_ids
    return if signed_ids.empty?

    page.photos.attach(signed_ids)
    page.retained_photo_signed_ids = []
  end

  def raw_page_attributes
    params.fetch(:page, {})
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
      .where.not(id: @page.chapter_id)
      .find_by(id: move_destination_chapter_id)
  end

  def assign_pending_content_from_params(page, attrs, raw_attrs)
    page.pending_voice_note_uploads = raw_voice_note_uploads(raw_attrs)
    page.pending_voice_note_duration_seconds = Array(attrs[:voice_note_duration_seconds])
    page.pending_voice_note_recorded_ats = Array(attrs[:voice_note_recorded_ats])
    page.pending_todo_list_enabled = attrs[:todo_list_enabled]
    page.pending_todo_list_hide_completed = attrs[:todo_list_hide_completed]
    page.pending_todo_item_contents = Array(attrs[:todo_item_contents])
    page.pending_scanned_document_payloads = parse_pending_scanned_document_payloads(attrs[:pending_scanned_documents_json])
  end

  def raw_voice_note_uploads(raw_attrs)
    Array(raw_attrs[:voice_note_uploads]).filter_map do |upload|
      next if upload.blank?
      next upload if upload.respond_to?(:content_type)

      nil
    end
  end

  def persist_pending_voice_notes(page)
    return unless VoiceNote.schema_ready?

    uploads = page.pending_voice_note_uploads
    return if uploads.empty?

    uploads.each_with_index do |upload, index|
      next unless upload.respond_to?(:content_type)

      voice_note = page.voice_notes.new(
        duration_seconds: normalized_voice_note_duration(page, index),
        recorded_at: normalized_voice_note_recorded_at(page, index),
        byte_size: upload.size,
        mime_type: upload.content_type.to_s
      )
      voice_note.audio.attach(upload)
      voice_note.save!
    end

    page.pending_voice_note_uploads = []
  end

  def normalized_voice_note_duration(page, index)
    page.pending_voice_note_duration_seconds[index].to_i.clamp(0, VoiceNote::MAX_DURATION_SECONDS)
  end

  def normalized_voice_note_recorded_at(page, index)
    Time.zone.parse(page.pending_voice_note_recorded_ats[index].to_s)
  rescue ArgumentError, TypeError
    Time.current
  end

  def persist_pending_todo_list(page, attrs)
    return unless TodoList.schema_ready? && TodoItem.schema_ready?

    item_contents = Array(attrs[:todo_item_contents]).filter_map { |content| content.to_s.squish.presence }
    should_enable = ActiveModel::Type::Boolean.new.cast(attrs[:todo_list_enabled]) || item_contents.any?
    should_hide_completed = ActiveModel::Type::Boolean.new.cast(attrs[:todo_list_hide_completed]) == true
    return unless should_enable || page.todo_list.present?

    todo_list = page.todo_list || page.build_todo_list
    todo_list.enabled = should_enable
    todo_list.hide_completed = should_hide_completed
    todo_list.save! if todo_list.new_record? || todo_list.changed?

    item_contents.each do |content|
      todo_list.todo_items.create!(content: content)
    end

    page.pending_todo_item_contents = []
  end

  def schedule_drive_export(page)
    Drive::ScheduleRecordExport.new(record: page).call
  end

  def move_page_to_chapter
    destination_chapter = move_destination_chapter

    unless destination_chapter
      @page.errors.add(:base, "Choose a notebook chapter to move this page into.")
      return render :show, status: :unprocessable_entity
    end

    source_chapter = @page.chapter

    Page.transaction do
      @page.update!(
        chapter: destination_chapter,
        position: next_page_position_for(destination_chapter)
      )
      normalize_page_positions!(source_chapter)
    end

    schedule_drive_export(@page)

    redirect_to notebook_chapter_page_path(destination_chapter.notebook, destination_chapter, @page),
      notice: "Page moved to #{destination_chapter.notebook.title} / #{destination_chapter.title}."
  rescue ActiveRecord::RecordInvalid
    render :show, status: :unprocessable_entity
  end

  def page_detail_includes
    includes = []
    includes << { voice_notes: [audio_attachment: :blob] } if VoiceNote.schema_ready?

    if TodoList.schema_ready? && TodoItem.schema_ready?
      includes << if Reminder.schema_ready?
        { todo_list: { todo_items: :reminder } }
      else
        { todo_list: :todo_items }
      end
    end

    includes
  end


  def move_within_scope(scope, record, direction)
    items = scope.to_a
    index = items.index(record)
    return if index.nil?

    swap_index = direction == "up" ? index - 1 : index + 1
    return if swap_index.negative? || swap_index >= items.length

    other = items[swap_index]

    record.class.transaction do
      record_position = record.position
      record.update!(position: other.position)
      other.update!(position: record_position)
    end
  end

  def next_page_position_for(chapter)
    chapter.pages.maximum(:position).to_i + 1
  end

  def normalize_page_positions!(chapter)
    chapter.pages.ordered.each_with_index do |page, index|
      desired_position = index + 1
      next if page.position == desired_position

      page.update!(position: desired_position)
    end
  end

  def move_destination_label(chapter)
    return if chapter.blank?

    "#{chapter.notebook.title} > #{chapter.title}"
  end
end
