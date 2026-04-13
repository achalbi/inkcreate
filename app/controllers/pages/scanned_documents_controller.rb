module Pages
  class ScannedDocumentsController < BaseController
    include ScannedDocumentSupport

    def create
      doc = @page.scanned_documents.new(scanned_document_params)
      doc.user = current_user

      if params.dig(:scanned_document, :image_data).present?
        attach_scanned_document_assets(doc, params[:scanned_document][:image_data])
      end

      if doc.save
        respond_to do |fmt|
          fmt.html { redirect_to notebook_chapter_page_path(@notebook, @chapter, @page), notice: "Document saved." }
          fmt.json { render json: { ok: true } }
        end
      else
        respond_to do |fmt|
          fmt.html { redirect_to notebook_chapter_page_path(@notebook, @chapter, @page), alert: doc.errors.full_messages.to_sentence }
          fmt.json { render json: { ok: false, error: doc.errors.full_messages.to_sentence }, status: :unprocessable_entity }
        end
      end
    end

    def extract_text
      return redirect_to(notebook_chapter_page_path(@notebook, @chapter, @page), alert: "OCR is turned off in Privacy settings.") unless current_user.ensure_app_setting!.allow_ocr_processing?

      doc = @page.scanned_documents.find(params[:id])
      ScannedDocuments::RunOcr.new(scanned_document: doc).call

      respond_to do |fmt|
        fmt.html { redirect_to notebook_chapter_page_path(@notebook, @chapter, @page), notice: "Text extracted." }
        fmt.json { render json: { ok: true, extracted_text: doc.extracted_text.to_s } }
      end
    rescue StandardError => error
      respond_to do |fmt|
        fmt.html { redirect_to notebook_chapter_page_path(@notebook, @chapter, @page), alert: error.message }
        fmt.json { render json: { ok: false, error: error.message }, status: :unprocessable_entity }
      end
    end

    def submit_ocr_result
      return redirect_to(notebook_chapter_page_path(@notebook, @chapter, @page), alert: "OCR is turned off in Privacy settings.") unless current_user.ensure_app_setting!.allow_ocr_processing?

      doc = @page.scanned_documents.find(params[:id])
      ScannedDocuments::ApplyOcrResult.new(scanned_document: doc, **ocr_result_params.to_h.symbolize_keys).call

      respond_to do |fmt|
        fmt.html { redirect_to notebook_chapter_page_path(@notebook, @chapter, @page), notice: "Text extracted." }
        fmt.json { render json: { ok: true, extracted_text: doc.extracted_text.to_s, ocr_engine: doc.ocr_engine.to_s } }
      end
    rescue StandardError => error
      respond_to do |fmt|
        fmt.html { redirect_to notebook_chapter_page_path(@notebook, @chapter, @page), alert: error.message }
        fmt.json { render json: { ok: false, error: error.message }, status: :unprocessable_entity }
      end
    end

    def ocr_source
      return render json: { ok: false, error: "OCR is turned off in Privacy settings." }, status: :forbidden unless current_user.ensure_app_setting!.allow_ocr_processing?

      doc = @page.scanned_documents.find(params[:id])
      render json: { ok: true, image_data_url: ScannedDocuments::ImageDataUrl.new(scanned_document: doc).call }
    rescue StandardError => error
      render json: { ok: false, error: error.message }, status: :unprocessable_entity
    end

    def destroy
      doc = @page.scanned_documents.find(params[:id])
      doc.destroy!
      respond_to do |fmt|
        fmt.html { redirect_back fallback_location: notebook_chapter_page_path(@notebook, @chapter, @page), notice: "Document deleted." }
        fmt.json { render json: { ok: true } }
      end
    end

    private

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
  end
end
