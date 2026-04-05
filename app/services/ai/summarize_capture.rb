module Ai
  class SummarizeCapture
    def initialize(capture:, user:)
      @capture = capture
      @user = user
    end

    def call
      capture.update!(ai_status: :processing)
      result = ProviderFactory.build.summarize_capture(capture)

      summary = capture.ai_summaries.create!(
        provider: result.raw_payload.fetch(:provider, "null"),
        summary: result.summary,
        bullets: result.bullets,
        tasks_extracted: result.tasks,
        entities: result.entities,
        raw_payload: result.raw_payload
      )

      result.tasks.each do |task_payload|
        user.tasks.find_or_create_by!(
          capture: capture,
          project: capture.project,
          daily_log: capture.daily_log,
          title: task_payload.fetch(:title)
        ) do |task|
          task.description = "Extracted from AI summary"
          task.priority = :medium
        end
      end

      capture.update!(ai_status: :completed)
      summary
    rescue StandardError
      capture.update!(ai_status: :failed)
      raise
    end

    private

    attr_reader :capture, :user
  end
end
