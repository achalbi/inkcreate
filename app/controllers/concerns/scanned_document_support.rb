module ScannedDocumentSupport
  private

  def attach_scanned_document_image(doc, data_url)
    match = data_url.to_s.match(/\Adata:([\w\/.+-]+);base64,(.+)\z/m)
    return unless match

    content_type = match[1]
    binary = Base64.decode64(match[2])
    ext = content_type.split("/").last

    doc.enhanced_image.attach(
      io: StringIO.new(binary),
      filename: "scan_#{Time.current.to_i}.#{ext}",
      content_type: content_type
    )
  end

  def parse_pending_scanned_document_payloads(raw_json)
    parsed = JSON.parse(raw_json.to_s)

    Array(parsed).filter_map do |payload|
      normalize_scanned_document_payload(payload)
    end
  rescue JSON::ParserError, TypeError
    []
  end

  def persist_pending_scanned_documents(owner, payloads:, user:)
    Array(payloads).each do |payload|
      normalized_payload = normalize_scanned_document_payload(payload)
      next if normalized_payload.blank?

      doc = owner.scanned_documents.new(
        title: normalized_payload["title"].presence || default_scanned_document_title,
        extracted_text: normalized_payload["extracted_text"],
        ocr_engine: normalized_payload["ocr_engine"].presence || "tesseract",
        ocr_language: normalized_payload["ocr_language"].presence || "eng",
        ocr_confidence: normalized_payload["ocr_confidence"].presence || 0,
        enhancement_filter: normalized_payload["enhancement_filter"].presence || "auto",
        tags: normalize_scanned_document_tags(normalized_payload["tags"])
      )
      doc.user = user

      attach_scanned_document_image(doc, normalized_payload["image_data"]) if normalized_payload["image_data"].present?
      doc.save!
    end
  end

  def normalize_scanned_document_payload(payload)
    hash = case payload
    when ActionController::Parameters
      payload.to_unsafe_h
    when Hash
      payload
    else
      nil
    end

    return if hash.blank?

    hash.stringify_keys.slice(
      "title",
      "extracted_text",
      "ocr_engine",
      "ocr_language",
      "ocr_confidence",
      "enhancement_filter",
      "tags",
      "image_data"
    )
  end

  def normalize_scanned_document_tags(tags)
    return tags if tags.is_a?(String)

    Array(tags).map { |tag| tag.to_s.strip }.reject(&:blank?).to_json
  end

  def default_scanned_document_title
    "Scan — #{Time.zone.today.strftime("%b %-d, %Y")}"
  end
end
