module Pages
  class VoiceNotesController < BaseController
    def create
      upload = voice_note_params.fetch(:audio)
      voice_note = @page.voice_notes.new(
        duration_seconds: normalized_duration_seconds,
        recorded_at: normalized_recorded_at,
        byte_size: upload.size,
        mime_type: upload.content_type.to_s
      )
      voice_note.audio.attach(upload)
      voice_note.save!

      if request.format.json?
        render json: { ok: true, message: "Voice note saved." }
      else
        redirect_to notebook_chapter_page_path(@notebook, @chapter, @page), notice: "Voice note saved."
      end
    rescue ActionController::ParameterMissing, ActiveRecord::RecordInvalid => error
      if request.format.json?
        render json: { ok: false, error: error.message }, status: :unprocessable_entity
      else
        redirect_to notebook_chapter_page_path(@notebook, @chapter, @page), alert: error.message
      end
    end

    def destroy
      voice_note = @page.voice_notes.find(params[:id])
      voice_note.destroy!

      if request.format.json?
        render json: { ok: true, message: "Voice note deleted." }
      else
        redirect_back fallback_location: notebook_chapter_page_path(@notebook, @chapter, @page), notice: "Voice note deleted."
      end
    end

    private

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
  end
end
