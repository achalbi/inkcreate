module Drive
  class OauthState
    PURPOSE = "drive-oauth".freeze
    EXPIRY = 15.minutes

    class << self
      def generate(user:, return_to: nil, popup: false)
        verifier.generate(
          {
            "user_id" => user.id,
            "return_to" => return_to.presence,
            "popup" => popup == true,
            "nonce" => SecureRandom.hex(12)
          },
          expires_in: EXPIRY,
          purpose: PURPOSE
        )
      end

      def verify(token)
        payload = verifier.verified(token, purpose: PURPOSE)
        return unless payload.is_a?(Hash)
        return if payload["user_id"].blank?

        payload
      rescue ActiveSupport::MessageVerifier::InvalidSignature
        nil
      end

      private

      def verifier
        Rails.application.message_verifier(PURPOSE)
      end
    end
  end
end
