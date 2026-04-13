module NotepadEntries
  class ScannedDocumentsController < BrowserController
    include ScannedDocumentSupport

    before_action :require_authenticated_user!
    before_action :set_notepad_entry

    def create
      doc = @notepad_entry.scanned_documents.new(scanned_document_params)
      doc.user = current_user

      if params[:scanned_document][:image_data].present?
        attach_scanned_document_image(doc, params[:scanned_document][:image_data])
      end

      if doc.save
        respond_to do |fmt|
          fmt.html { redirect_to notepad_entry_path(@notepad_entry), notice: "Document saved." }
          fmt.json { render json: { ok: true } }
        end
      else
        respond_to do |fmt|
          fmt.html { redirect_to notepad_entry_path(@notepad_entry), alert: doc.errors.full_messages.to_sentence }
          fmt.json { render json: { ok: false, error: doc.errors.full_messages.to_sentence }, status: :unprocessable_entity }
        end
      end
    end

    def destroy
      doc = @notepad_entry.scanned_documents.find(params[:id])
      doc.destroy!

      respond_to do |fmt|
        fmt.html { redirect_back fallback_location: notepad_entry_path(@notepad_entry), notice: "Document deleted." }
        fmt.json { render json: { ok: true } }
      end
    end

    private

    def set_notepad_entry
      @notepad_entry = current_user.notepad_entries.find(params[:notepad_entry_id])
    end

    def scanned_document_params
      params.require(:scanned_document).permit(
        :title, :extracted_text,
        :ocr_engine, :ocr_language, :ocr_confidence,
        :enhancement_filter, :tags
      )
    end
  end
end
