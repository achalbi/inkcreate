module NotepadEntries
  class ScannedDocumentsController < BrowserController
    include ScannedDocumentSupport
    include DriveRecordExportScheduling

    before_action :require_authenticated_user!
    before_action :set_notepad_entry

    def create
      doc = @notepad_entry.scanned_documents.new(scanned_document_params)
      doc.user = current_user
      doc.title = next_scanned_document_title_for(@notepad_entry, doc.title.presence || default_scanned_document_title)

      if params.dig(:scanned_document, :image_data).present?
        attach_scanned_document_assets(
          doc,
          params[:scanned_document][:image_data],
          pdf_data: params.dig(:scanned_document, :pdf_data)
        )
      end

      if doc.save
        respond_to do |fmt|
          fmt.html { redirect_to notepad_entry_path(@notepad_entry), notice: "Document saved." }
          fmt.json do
            render json: {
              ok: true,
              scanned_document_id: doc.id,
              submit_ocr_result_url: submit_ocr_result_notepad_entry_scanned_document_path(@notepad_entry, doc),
              ocr_source_url: ocr_source_notepad_entry_scanned_document_path(@notepad_entry, doc)
            }
          end
        end
      else
        respond_to do |fmt|
          fmt.html { redirect_to notepad_entry_path(@notepad_entry), alert: doc.errors.full_messages.to_sentence }
          fmt.json { render json: { ok: false, error: doc.errors.full_messages.to_sentence }, status: :unprocessable_entity }
        end
      end
    end

    def extract_text
      return redirect_to(notepad_entry_path(@notepad_entry), alert: "OCR is turned off in Privacy settings.") unless current_user.ensure_app_setting!.allow_ocr_processing?

      doc = @notepad_entry.scanned_documents.find(params[:id])
      ScannedDocuments::RunOcr.new(scanned_document: doc).call

      respond_to do |fmt|
        fmt.html { redirect_to notepad_entry_path(@notepad_entry), notice: "Text extracted." }
        fmt.json { render json: { ok: true, extracted_text: doc.extracted_text.to_s } }
      end
    rescue StandardError => error
      respond_to do |fmt|
        fmt.html { redirect_to notepad_entry_path(@notepad_entry), alert: error.message }
        fmt.json { render json: { ok: false, error: error.message }, status: :unprocessable_entity }
      end
    end

    def submit_ocr_result
      return redirect_to(notepad_entry_path(@notepad_entry), alert: "OCR is turned off in Privacy settings.") unless current_user.ensure_app_setting!.allow_ocr_processing?

      doc = @notepad_entry.scanned_documents.find(params[:id])
      ScannedDocuments::ApplyOcrResult.new(scanned_document: doc, **ocr_result_params.to_h.symbolize_keys).call

      respond_to do |fmt|
        fmt.html { redirect_to notepad_entry_path(@notepad_entry), notice: "Text extracted." }
        fmt.json { render json: { ok: true, extracted_text: doc.extracted_text.to_s, ocr_engine: doc.ocr_engine.to_s } }
      end
    rescue StandardError => error
      respond_to do |fmt|
        fmt.html { redirect_to notepad_entry_path(@notepad_entry), alert: error.message }
        fmt.json { render json: { ok: false, error: error.message }, status: :unprocessable_entity }
      end
    end

    def ocr_source
      return render json: { ok: false, error: "OCR is turned off in Privacy settings." }, status: :forbidden unless current_user.ensure_app_setting!.allow_ocr_processing?

      doc = @notepad_entry.scanned_documents.find(params[:id])
      render json: { ok: true, image_data_url: ScannedDocuments::ImageDataUrl.new(scanned_document: doc).call }
    rescue StandardError => error
      render json: { ok: false, error: error.message }, status: :unprocessable_entity
    end

    def show_text
      doc = @notepad_entry.scanned_documents.find(params[:id])
      render partial: "shared/scanned_document_text_viewer",
             locals: viewer_locals(doc)
    end

    def edit_text
      doc = @notepad_entry.scanned_documents.find(params[:id])
      render partial: "shared/scanned_document_text_editor",
             locals: editor_locals(doc)
    end

    def confirm_delete_text
      doc = @notepad_entry.scanned_documents.find(params[:id])
      render partial: "shared/scanned_document_text_delete_confirm",
             locals: delete_confirm_locals(doc)
    end

    def update_text
      doc = @notepad_entry.scanned_documents.find(params[:id])
      doc.update!(extracted_text: params[:extracted_text].to_s.strip)
      render partial: "shared/scanned_document_text_viewer",
             locals: viewer_locals(doc, saved_notice: "OCR text saved.")
    end

    def delete_text
      doc = @notepad_entry.scanned_documents.find(params[:id])
      doc.update!(
        extracted_text: nil,
        ocr_engine: nil,
        ocr_language: nil,
        ocr_confidence: nil
      )

      redirect_to notepad_entry_path(@notepad_entry), notice: "OCR text deleted."
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
        :title,
        :enhancement_filter,
        :tags
      )
    end

    def ocr_result_params
      params.require(:ocr_result).permit(
        :text,
        :confidence,
        :language,
        :engine
      )
    end

    def requested_frame_id_for(doc)
      params[:frame_id].presence || ActionView::RecordIdentifier.dom_id(doc, :text)
    end

    def viewer_locals(doc, saved_notice: nil)
      frame_id = requested_frame_id_for(doc)

      {
        doc: doc,
        frame_id: frame_id,
        edit_url: edit_text_notepad_entry_scanned_document_path(@notepad_entry, doc, frame_id: frame_id),
        delete_confirm_url: confirm_delete_text_notepad_entry_scanned_document_path(@notepad_entry, doc, frame_id: frame_id),
        saved_notice: saved_notice
      }
    end

    def editor_locals(doc)
      frame_id = requested_frame_id_for(doc)

      {
        doc: doc,
        frame_id: frame_id,
        update_url: update_text_notepad_entry_scanned_document_path(@notepad_entry, doc, frame_id: frame_id),
        view_url: show_text_notepad_entry_scanned_document_path(@notepad_entry, doc, frame_id: frame_id),
        delete_confirm_url: confirm_delete_text_notepad_entry_scanned_document_path(@notepad_entry, doc, frame_id: frame_id)
      }
    end

    def delete_confirm_locals(doc)
      frame_id = requested_frame_id_for(doc)

      {
        doc: doc,
        frame_id: frame_id,
        delete_url: delete_text_notepad_entry_scanned_document_path(@notepad_entry, doc),
        view_url: show_text_notepad_entry_scanned_document_path(@notepad_entry, doc, frame_id: frame_id)
      }
    end
  end
end
