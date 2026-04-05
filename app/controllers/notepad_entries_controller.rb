class NotepadEntriesController < BrowserController
  before_action :require_authenticated_user!
  before_action :set_notepad_entry, only: %i[show edit update destroy destroy_photo]

  def index
    entries = current_user.notepad_entries.with_attached_photos.recent_first
    @entries_by_date = entries.group_by(&:entry_date)
  end

  def show; end

  def new
    @notepad_entry = current_user.notepad_entries.new(entry_date: Date.current)
  end

  def create
    @notepad_entry = current_user.notepad_entries.new(notepad_entry_attributes)

    if @notepad_entry.save
      attach_photos(@notepad_entry)
      redirect_to notepad_entry_path(@notepad_entry), notice: "Notepad entry created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @notepad_entry.update(notepad_entry_attributes)
      attach_photos(@notepad_entry)
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
    redirect_to notepad_entry_path(@notepad_entry), notice: "Photo removed."
  end

  private

  def set_notepad_entry
    @notepad_entry = current_user.notepad_entries.with_attached_photos.find(params[:id])
  end

  def notepad_entry_params
    params.require(:notepad_entry).permit(:title, :notes, :entry_date, photos: [])
  end

  def notepad_entry_attributes
    notepad_entry_params.except(:photos)
  end

  def attach_photos(entry)
    files = Array(notepad_entry_params[:photos]).reject(&:blank?)
    entry.photos.attach(files) if files.any?
  end
end
