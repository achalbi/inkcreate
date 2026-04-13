module ScannedDocumentSupport
  AUTO_SCANNED_DOCUMENT_TITLE_REGEX = /\A(?<base>Scan [—-] .+?)(?: #(?<suffix>\d+))?\z/

  private

  def attach_scanned_document_assets(doc, image_data_url, pdf_data: nil)
    image_payload = decoded_data_url_payload(image_data_url)
    return false unless image_payload

    ext = image_payload[:content_type].split("/").last.presence || "jpg"
    base_filename = scanned_document_filename_base(doc.title)

    doc.enhanced_image.attach(
      io: StringIO.new(image_payload[:binary]),
      filename: "#{base_filename}.#{ext}",
      content_type: image_payload[:content_type]
    )

    doc.document_pdf.attach(
      io: StringIO.new(scanned_document_pdf_binary(pdf_data, fallback_image_binary: image_payload[:binary])),
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
    used_titles = owner.scanned_documents.pluck(:title)

    Array(payloads).each do |payload|
      normalized_payload = normalize_scanned_document_payload(payload)
      next if normalized_payload.blank?

      doc = owner.scanned_documents.new(
        title: next_scanned_document_title_for(
          owner,
          normalized_payload["title"].presence || default_scanned_document_title,
          used_titles: used_titles
        ),
        enhancement_filter: normalized_payload["enhancement_filter"].presence || "auto",
        tags: normalize_scanned_document_tags(normalized_payload["tags"])
      )
      doc.user = user

      attach_scanned_document_assets(
        doc,
        normalized_payload["image_data"],
        pdf_data: normalized_payload["pdf_data"]
      ) if normalized_payload["image_data"].present?
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
      "image_data",
      "pdf_data"
    )
  end

  def normalize_scanned_document_tags(tags)
    return tags if tags.is_a?(String)

    Array(tags).map { |tag| tag.to_s.strip }.reject(&:blank?).to_json
  end

  def default_scanned_document_title
    "Scan — #{Time.zone.now.strftime("%b %-d, %Y %H:%M:%S")}"
  end

  def next_scanned_document_title_for(owner, preferred_title, used_titles: nil)
    title = preferred_title.to_s.strip.presence || default_scanned_document_title
    match = title.match(AUTO_SCANNED_DOCUMENT_TITLE_REGEX)
    return title unless match

    titles = used_titles || owner.scanned_documents.pluck(:title)
    unless titles.include?(title)
      used_titles&.push(title)
      return title
    end

    base = match[:base]
    next_suffix = titles.filter_map do |existing_title|
      existing_match = existing_title.to_s.match(/\A#{Regexp.escape(base)}(?: #(?<suffix>\d+))?\z/)
      next unless existing_match

      existing_match[:suffix].present? ? existing_match[:suffix].to_i : 1
    end.max.to_i + 1

    unique_title = "#{base} ##{next_suffix}"
    used_titles&.push(unique_title)
    unique_title
  end

  def scanned_document_filename_base(title)
    title.to_s.parameterize.presence || "scan-#{Time.current.to_i}"
  end

  def decoded_data_url_payload(data_url)
    match = data_url.to_s.match(/\Adata:([\w\/.+-]+);base64,(.+)\z/m)
    return unless match

    {
      content_type: match[1],
      binary: Base64.decode64(match[2])
    }
  end

  def scanned_document_pdf_binary(pdf_data, fallback_image_binary:)
    pdf_payload = decoded_data_url_payload(pdf_data)
    return pdf_payload[:binary] if pdf_payload&.dig(:content_type).to_s.include?("pdf")

    ScannedDocuments::PdfBuilder.new(image_binary: fallback_image_binary).call
  end
end
