class WebPushDeliverer
  DEAD_SUBSCRIPTION_CODES = %w[404 410].freeze

  class << self
    def configured?
      public_key.present? && private_key.present? && subject.present?
    end

    def public_key
      vapid_config[:public_key]
    end

    def deliver(device:, payload:)
      return unless configured?

      WebPush.payload_send(
        message: payload.to_json,
        endpoint: device.push_endpoint,
        p256dh: device.push_p256dh_key,
        auth: device.push_auth_key,
        vapid: {
          subject: subject,
          public_key: public_key,
          private_key: private_key
        },
        ttl: 60
      )
    rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription
      device.disable_push!
    rescue WebPush::ResponseError => error
      if DEAD_SUBSCRIPTION_CODES.include?(error.response&.code.to_s)
        device.disable_push!
      else
        raise
      end
    end

    private

    def private_key
      vapid_config[:private_key]
    end

    def subject
      vapid_config[:subject]
    end

    def vapid_config
      credentials = Rails.application.credentials

      {
        public_key: ENV["VAPID_PUBLIC_KEY"].presence || credentials.dig(:vapid, :public_key),
        private_key: ENV["VAPID_PRIVATE_KEY"].presence || credentials.dig(:vapid, :private_key),
        subject: ENV["VAPID_SUBJECT"].presence || credentials.dig(:vapid, :subject)
      }
    end
  end
end
