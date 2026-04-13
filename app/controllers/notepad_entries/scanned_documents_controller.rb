module NotepadEntries
  class ScannedDocumentsController < BaseController
    def create
      doc = @notepad_entry.scanned_documents.new(scanned_document_params)
      doc.user = current_user

      # Attach the enhanced image — sent as a multipart file upload from the browser
      if params[:scanned_document][:enhanced_image].present?
        doc.enhanced_image.attach(params[:scanned_document][:enhanced_image])
      elsif params[:scanned_document][:image_data].present?
        # Legacy base64 data-URL fallback
        attach_image(doc, params[:scanned_document][:image_data])
      end

      # Attach PDF if provided as a multipart upload
      if params[:scanned_document][:pdf_document].present?
        doc.pdf_document.attach(params[:scanned_document][:pdf_document])
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

    def run_ocr
      doc = @notepad_entry.scanned_documents.find(params[:id])

      unless doc.enhanced_image.attached?
        respond_to do |fmt|
          fmt.html { redirect_back fallback_location: notepad_entry_path(@notepad_entry), alert: "No image to run OCR on." }
          fmt.json { render json: { ok: false, error: "No image attached" }, status: :unprocessable_entity }
        end
        return
      end

      result = run_tesseract(doc)

      if result
        doc.update!(
          extracted_text: result[:text],
          ocr_engine: "tesseract",
          ocr_language: ENV.fetch("OCR_LANGUAGE", "eng"),
          ocr_confidence: result[:confidence]
        )
        respond_to do |fmt|
          fmt.html { redirect_back fallback_location: notepad_entry_path(@notepad_entry), notice: "OCR complete." }
          fmt.json { render json: { ok: true, extracted_text: result[:text], confidence: result[:confidence] } }
        end
      else
        respond_to do |fmt|
          fmt.html { redirect_back fallback_location: notepad_entry_path(@notepad_entry), alert: "OCR failed." }
          fmt.json { render json: { ok: false, error: "OCR failed" }, status: :unprocessable_entity }
        end
      end
    end

    private

    def scanned_document_params
      params.require(:scanned_document).permit(
        :title, :enhancement_filter, :tags
      )
    end

    def attach_image(doc, data_url)
      match = data_url.match(/\Adata:([\w\/]+);base64,(.+)\z/m)
      return unless match

      content_type = match[1]
      binary       = Base64.decode64(match[2])
      ext          = content_type.split("/").last

      doc.enhanced_image.attach(
        io:           StringIO.new(binary),
        filename:     "scan_#{Time.current.to_i}.#{ext}",
        content_type: content_type
      )
    end

    def run_tesseract(doc)
      doc.enhanced_image.blob.open do |tmpfile|
        provider = Ocr::TesseractProvider.new
        result = provider.call(image_path: tmpfile.path)
        {
          text: result.cleaned_text,
          confidence: nil
        }
      end
    rescue => e
      Rails.logger.error("OCR failed for ScannedDocument##{doc.id}: #{e.message}")
      nil
    end
  end
end
