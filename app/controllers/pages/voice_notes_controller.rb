module Pages
  class VoiceNotesController < BaseController
    def create
      upload = voice_note_params.fetch(:audio)
      duration_seconds = normalized_duration_seconds
      recorded_at = normalized_recorded_at
      byte_size = upload.size
      mime_type = upload.content_type.to_s

      voice_note = @page.with_lock do
        find_duplicate_voice_note(
          duration_seconds: duration_seconds,
          recorded_at: recorded_at,
          byte_size: byte_size,
          mime_type: mime_type
        ) || @page.voice_notes.create!(
          audio: upload,
          duration_seconds: duration_seconds,
          recorded_at: recorded_at,
          byte_size: byte_size,
          mime_type: mime_type
        )
      end

      if request.format.json?
        render json: { ok: true, message: "Voice note saved.", id: voice_note.id }
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

    def submit_transcript
      voice_note = @page.voice_notes.find(params[:id])
      voice_note.update!(transcript: normalized_transcript_text)

      respond_to do |format|
        format.html { redirect_to notebook_chapter_page_path(@notebook, @chapter, @page), notice: "Transcript saved." }
        format.json { render json: { ok: true, transcript: voice_note.transcript.to_s } }
      end
    rescue ActionController::ParameterMissing, ActiveRecord::RecordInvalid, ArgumentError => error
      respond_to do |format|
        format.html { redirect_to notebook_chapter_page_path(@notebook, @chapter, @page), alert: error.message }
        format.json { render json: { ok: false, error: error.message }, status: :unprocessable_entity }
      end
    end

    private

    def voice_note_params
      params.require(:voice_note).permit(:audio, :duration_seconds, :recorded_at)
    end

    def transcript_result_params
      params.require(:transcript_result).permit(:text)
    end

    def normalized_duration_seconds
      voice_note_params[:duration_seconds].to_i.clamp(0, VoiceNote::MAX_DURATION_SECONDS)
    end

    def normalized_recorded_at
      Time.zone.parse(voice_note_params[:recorded_at].to_s)
    rescue ArgumentError, TypeError
      Time.current
    end

    def normalized_transcript_text
      transcript = transcript_result_params[:text].to_s.strip
      return transcript if transcript.present?

      raise ArgumentError, "Transcript text can't be blank."
    end

    def find_duplicate_voice_note(duration_seconds:, recorded_at:, byte_size:, mime_type:)
      @page.voice_notes.find_by(
        duration_seconds: duration_seconds,
        recorded_at: recorded_at,
        byte_size: byte_size,
        mime_type: mime_type
      )
    end
  end
end
