module Pages
  class ScannedDocumentsController < BaseController
    def create
      doc = @page.scanned_documents.new(scanned_document_params)
      doc.user = current_user

      # Attach the enhanced image blob sent as a base64 data-URL from the browser
      if params[:scanned_document][:image_data].present?
        attach_image(doc, params[:scanned_document][:image_data])
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
        :title, :extracted_text,
        :ocr_engine, :ocr_language, :ocr_confidence,
        :enhancement_filter, :tags
      )
    end

    def attach_image(doc, data_url)
      # data_url looks like "data:image/jpeg;base64,/9j/4AAQ..."
      match = data_url.match(/\Adata:([\w\/]+);base64,(.+)\z/m)
      return unless match

      content_type = match[1]               # e.g. "image/jpeg"
      binary       = Base64.decode64(match[2])
      ext          = content_type.split("/").last  # "jpeg"

      doc.enhanced_image.attach(
        io:           StringIO.new(binary),
        filename:     "scan_#{Time.current.to_i}.#{ext}",
        content_type: content_type
      )
    end
  end
end
