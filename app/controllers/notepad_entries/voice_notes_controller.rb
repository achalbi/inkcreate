module NotepadEntries
  class VoiceNotesController < BrowserController
    before_action :require_authenticated_user!
    before_action :ensure_voice_notes_supported!
    before_action :set_notepad_entry

    def create
      upload = voice_note_params.fetch(:audio)
      voice_note = @notepad_entry.voice_notes.new(
        duration_seconds: normalized_duration_seconds,
        recorded_at: normalized_recorded_at,
        byte_size: upload.size,
        mime_type: upload.content_type.to_s
      )
      voice_note.audio.attach(upload)
      voice_note.save!
      schedule_drive_export

      if request.format.json?
        render json: { ok: true, message: "Voice note saved." }
      else
        redirect_to notepad_entry_path(@notepad_entry), notice: "Voice note saved."
      end
    rescue ActionController::ParameterMissing, ActiveRecord::RecordInvalid => error
      if request.format.json?
        render json: { ok: false, error: error.message }, status: :unprocessable_entity
      else
        redirect_to notepad_entry_path(@notepad_entry), alert: error.message
      end
    end

    def destroy
      voice_note = @notepad_entry.voice_notes.find(params[:id])
      voice_note.destroy!
      schedule_drive_export

      if request.format.json?
        render json: { ok: true, message: "Voice note deleted." }
      else
        redirect_back fallback_location: notepad_entry_path(@notepad_entry), notice: "Voice note deleted."
      end
    end

    private

    def set_notepad_entry
      @notepad_entry = current_user.notepad_entries.find(params[:notepad_entry_id])
    end

    def voice_note_params
      params.require(:voice_note).permit(:audio, :duration_seconds, :recorded_at)
    end

    def normalized_duration_seconds
      voice_note_params[:duration_seconds].to_i.clamp(0, VoiceNote::MAX_DURATION_SECONDS)
    end

    def normalized_recorded_at
      Time.zone.parse(voice_note_params[:recorded_at].to_s)
    rescue ArgumentError, TypeError
      Time.current
    end

    def schedule_drive_export
      Drive::ScheduleRecordExport.new(record: @notepad_entry).call
    end

    def ensure_voice_notes_supported!
      head :not_found unless VoiceNote.notepad_entries_supported?
    end
  end
end
