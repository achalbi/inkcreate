Rails.application.configure do
  credentials = Rails.application.credentials

  config.active_record.encryption.primary_key =
    ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"].presence ||
    credentials.dig(:active_record_encryption, :primary_key)

  config.active_record.encryption.deterministic_key =
    ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"].presence ||
    credentials.dig(:active_record_encryption, :deterministic_key)

  config.active_record.encryption.key_derivation_salt =
    ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"].presence ||
    credentials.dig(:active_record_encryption, :key_derivation_salt)
end
