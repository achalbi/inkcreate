module Observability
  class EventLogger
    def self.info(event:, payload: {})
      Rails.logger.info(
        event: event,
        request_id: Current.request_id,
        user_id: Current.user&.id,
        payload: payload
      )
    end
  end
end
