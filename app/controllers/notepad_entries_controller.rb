class NotepadEntriesController < BrowserController
  GALLERY_ITEMS_PER_PAGE = 9

  before_action :require_authenticated_user!
  before_action :set_notepad_entry, only: %i[show edit update destroy destroy_photo]
  before_action :load_move_destination_groups, only: %i[edit update]

  def index
    @view_mode = index_view_mode
    @selected_entry_date = selected_entry_date
    entries = current_user.notepad_entries.with_attached_photos.recent_first
    entries = entries.where(entry_date: @selected_entry_date) if @selected_entry_date.present?
    @entries_by_date = entries.group_by(&:entry_date)
    prepare_gallery(entries)
  end

  def show; end

  def new
    @notepad_entry = current_user.notepad_entries.new(entry_date: Time.zone.today)
    @notepad_entry.title = @notepad_entry.display_title
  end

  def create
    @notepad_entry = current_user.notepad_entries.new(notepad_entry_attributes)
    preserve_pending_photos(@notepad_entry, notepad_entry_params)

    if @notepad_entry.save
      attach_pending_photos(@notepad_entry)
      schedule_drive_export(@notepad_entry)
      redirect_to create_redirect_path(@notepad_entry), notice: create_notice_message
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    preserve_pending_photos(@notepad_entry, notepad_entry_params)

    if moving_to_notebook_chapter?
      @notepad_entry.assign_attributes(notepad_entry_attributes)
      return move_notepad_entry_to_chapter
    end

    if @notepad_entry.update(notepad_entry_attributes)
      attach_pending_photos(@notepad_entry)
      schedule_drive_export(@notepad_entry)
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
    @notepad_entry = current_user.notepad_entries.with_attached_photos.find(params[:id])
  end

  def load_move_destination_groups
    @move_destination_notebooks = current_user.notebooks.includes(chapters: :pages).ordered.select do |notebook|
      notebook.chapters.any?
    end
    @selected_move_destination_chapter_id = move_destination_chapter_id
    @selected_move_destination_label = move_destination_label(move_destination_chapter)
  end

  def notepad_entry_params
    params.require(:notepad_entry).permit(:title, :notes, :entry_date, retained_photo_signed_ids: [], photos: [])
  end

  def notepad_entry_attributes
    notepad_entry_params.except(:photos, :retained_photo_signed_ids)
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

  def schedule_drive_export(entry)
    Drive::ScheduleRecordExport.new(record: entry).call
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

    NotepadEntry.transaction do
      page.save!
      attach_pending_photos(page)
      @notepad_entry.photos.detach
      @notepad_entry.destroy!
    end

    schedule_drive_export(page)
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

  def move_destination_label(chapter)
    return if chapter.blank?

    "#{chapter.notebook.title} > #{chapter.title}"
  end

  def create_redirect_path(entry)
    return edit_notepad_entry_path(entry) if redirect_to_edit_after_create?

    notepad_entry_path(entry)
  end

  def create_notice_message
    return "Daily page created. You can add notes or more photos now." if redirect_to_edit_after_create?

    "Notepad entry created."
  end

  def redirect_to_edit_after_create?
    params[:after_create].to_s == "edit"
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
