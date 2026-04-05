class CaptureSerializer
  def initialize(capture)
    @capture = capture
  end

  def as_json(*)
    {
      id: capture.id,
      notebook_id: capture.notebook_id,
      project_id: capture.project_id,
      daily_log_id: capture.daily_log_id,
      physical_page_id: capture.physical_page_id,
      page_template_key: capture.page_template&.key,
      page_type: capture.page_type,
      status: capture.status,
      ocr_status: capture.ocr_status,
      ai_status: capture.ai_status,
      backup_status: capture.backup_status,
      sync_status: capture.sync_status,
      title: capture.title,
      description: capture.description,
      original_filename: capture.original_filename,
      content_type: capture.content_type,
      byte_size: capture.byte_size,
      captured_at: capture.captured_at,
      meeting_label: capture.meeting_label,
      conference_label: capture.conference_label,
      project_label: capture.project_label,
      search_text: capture.search_text,
      classification_confidence: capture.classification_confidence,
      storage_bucket: capture.storage_bucket,
      storage_object_key: capture.storage_object_key,
      latest_ocr_result: serialize_ocr_result(capture.latest_ocr_result),
      latest_ai_summary: serialize_ai_summary(capture.latest_ai_summary),
      tags: capture.tags.order(:name).pluck(:name),
      favorite: capture.favorite,
      archived_at: capture.archived_at,
      created_at: capture.created_at,
      updated_at: capture.updated_at
    }
  end

  private

  attr_reader :capture

  def serialize_ocr_result(result)
    return nil unless result

    {
      provider: result.provider,
      cleaned_text: result.cleaned_text,
      mean_confidence: result.mean_confidence,
      language: result.language
    }
  end

  def serialize_ai_summary(summary)
    return nil unless summary

    {
      provider: summary.provider,
      summary: summary.summary,
      bullets: summary.bullets,
      tasks_extracted: summary.tasks_extracted,
      entities: summary.entities
    }
  end
end
