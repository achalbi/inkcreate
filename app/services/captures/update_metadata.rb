module Captures
  class UpdateMetadata
    def initialize(capture:, params:, user:)
      @capture = capture
      @params = params.deep_symbolize_keys
      @user = user
    end

    def call
      Capture.transaction do
        track_revision!
        capture.update!(update_attributes)
        assign_tags!
      end

      capture.reload
    end

    private

    attr_reader :capture, :params, :user

    def update_attributes
      {
        title: params[:title],
        description: params[:description],
        page_type: params[:page_type],
        favorite: params[:favorite],
        project: resolve_project,
        daily_log: resolve_daily_log,
        physical_page: resolve_physical_page
      }.compact
    end

    def resolve_project
      return capture.project unless params.key?(:project_id)
      return nil if params[:project_id].blank?

      user.projects.find(params[:project_id])
    end

    def resolve_daily_log
      return capture.daily_log unless params.key?(:daily_log_id)
      return nil if params[:daily_log_id].blank?

      user.daily_logs.find(params[:daily_log_id])
    end

    def resolve_physical_page
      return capture.physical_page unless params.key?(:physical_page_id)
      return nil if params[:physical_page_id].blank?

      user.physical_pages.find(params[:physical_page_id])
    end

    def assign_tags!
      return unless params.key?(:tags)

      capture.capture_tags.destroy_all

      normalized_tag_names.each do |tag_name|
        tag = user.tags.find_or_create_by!(name: tag_name)
        capture.capture_tags.find_or_create_by!(tag:)
      end
    end

    def track_revision!
      capture.capture_revisions.create!(
        revision_number: next_revision_number,
        metadata: {
          snapshot: capture.attributes.slice("title", "description", "page_type", "project_id", "daily_log_id", "favorite"),
          tags: capture.tags.order(:name).pluck(:name)
        }
      )
    end

    def next_revision_number
      capture.capture_revisions.maximum(:revision_number).to_i + 1
    end

    def normalized_tag_names
      Array(params[:tags]).flat_map { |value| value.to_s.split(",") }.map(&:strip).reject(&:blank?).uniq
    end
  end
end
