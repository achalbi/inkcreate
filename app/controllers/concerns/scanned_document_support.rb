module ScannedDocumentSupport
  private

  def attach_scanned_document_assets(doc, data_url)
    match = data_url.to_s.match(/\Adata:([\w\/.+-]+);base64,(.+)\z/m)
    return false unless match

    content_type = match[1]
    binary = Base64.decode64(match[2])
    ext = content_type.split("/").last.presence || "jpg"
    base_filename = scanned_document_filename_base(doc.title)

    doc.enhanced_image.attach(
      io: StringIO.new(binary),
      filename: "#{base_filename}.#{ext}",
      content_type: content_type
    )

    doc.document_pdf.attach(
      io: StringIO.new(ScannedDocuments::PdfBuilder.new(image_binary: binary).call),
      filename: "#{base_filename}.pdf",
      content_type: "application/pdf"
    )

    true
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
        enhancement_filter: normalized_payload["enhancement_filter"].presence || "auto",
        tags: normalize_scanned_document_tags(normalized_payload["tags"])
      )
      doc.user = user

      attach_scanned_document_assets(doc, normalized_payload["image_data"]) if normalized_payload["image_data"].present?
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

  def scanned_document_filename_base(title)
    title.to_s.parameterize.presence || "scan-#{Time.current.to_i}"
  end
end
