module SafePasswordAuthentication
  private

  def password_matches?(user, password)
    user&.valid_password?(password)
  rescue BCrypt::Errors::InvalidHash
    Rails.logger.warn(
      event: "auth.invalid_password_hash",
      user_id: user&.id,
      email: user&.email
    )
    false
  end
end
