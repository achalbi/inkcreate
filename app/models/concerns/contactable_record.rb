require "uri"
require "set"

module ContactableRecord
  extend ActiveSupport::Concern

  included do
    validate :contacts_are_valid

    before_validation :normalize_contacts_data
  end

  def contacts
    normalize_contact_collection(contact_data_source)
  end

  def contacts_json
    contacts.to_json
  end

  def contacts_json=(value)
    @contacts_json_input = value
  end

  def contact_entries
    contacts.map { |contact| decorate_contact(contact) }
  end

  def contact_count
    contact_entries.size
  end

  def multiple_contacts?
    contact_count > 1
  end

  def contact_present?
    contact_count.positive?
  end

  def contact_label
    primary_contact&.dig(:name)
  end

  def contact_count_label
    return if contact_count.zero?
    return contact_label if contact_count == 1

    "#{contact_count} contacts"
  end

  def contact_preview_text
    return if contact_count.zero?
    return primary_contact_preview_text if contact_count == 1

    "#{contact_label} +#{contact_count - 1} more contacts"
  end

  private

  def primary_contact
    contact_entries.first
  end

  def primary_contact_preview_text
    [contact_label, primary_contact_detail_text].compact.join(" · ")
  end

  def primary_contact_detail_text
    primary_contact&.dig(:primary_phone).presence ||
      primary_contact&.dig(:email).presence ||
      primary_contact&.dig(:website).presence
  end

  def decorate_contact(contact)
    {
      name: contact["name"],
      primary_phone: contact["primary_phone"],
      secondary_phone: contact["secondary_phone"],
      email: contact["email"],
      website: contact["website"],
      website_url: website_url_for(contact["website"]),
      primary_phone_href: phone_href_for(contact["primary_phone"]),
      secondary_phone_href: phone_href_for(contact["secondary_phone"]),
      email_href: email_href_for(contact["email"])
    }
  end

  def contacts_are_valid
    contacts.each_with_index do |contact, index|
      prefix = contact_count > 1 ? "Contact #{index + 1}" : "Contact"

      errors.add(:base, "#{prefix} name can't be blank.") if contact["name"].blank?
      errors.add(:base, "#{prefix} needs a phone, email, or website.") if contact_fields_blank?(contact)
      errors.add(:base, "#{prefix} email is invalid.") if invalid_contact_email?(contact)
      errors.add(:base, "#{prefix} website is invalid.") if invalid_contact_website?(contact)
      errors.add(:base, "#{prefix} primary phone is invalid.") if invalid_contact_phone?(contact["primary_phone"])
      errors.add(:base, "#{prefix} secondary phone is invalid.") if invalid_contact_phone?(contact["secondary_phone"])
    end
  end

  def invalid_contact_email?(contact)
    contact["email"].present? && !(contact["email"] =~ URI::MailTo::EMAIL_REGEXP)
  end

  def invalid_contact_website?(contact)
    contact["website"].present? && website_url_for(contact["website"]).blank?
  end

  def invalid_contact_phone?(value)
    value.present? && !phone_number_like?(value)
  end

  def normalize_contacts_data
    normalized_contacts = normalize_contact_collection(
      if contacts_json_input_present?
        parse_contacts_input(@contacts_json_input)
      else
        contact_data_source
      end
    )

    write_contacts_data(normalized_contacts)
    clear_contacts_json_input!
  end

  def contact_data_source
    return unless has_attribute?(:contacts_data)

    self[:contacts_data]
  end

  def write_contacts_data(contacts)
    return unless has_attribute?(:contacts_data)

    self[:contacts_data] = contacts
  end

  def contacts_json_input_present?
    instance_variable_defined?(:@contacts_json_input)
  end

  def clear_contacts_json_input!
    remove_instance_variable(:@contacts_json_input) if instance_variable_defined?(:@contacts_json_input)
  end

  def parse_contacts_input(value)
    case value
    when String
      stripped = value.strip
      return [] if stripped.blank?

      JSON.parse(stripped)
    when Array
      value
    when Hash, ActionController::Parameters
      [value]
    else
      []
    end
  rescue JSON::ParserError
    []
  end

  def normalize_contact_collection(collection)
    seen_signatures = Set.new

    Array(collection).filter_map do |entry|
      normalized_contact = normalized_contact(entry)
      next unless normalized_contact

      signature = contact_signature(normalized_contact)
      next if seen_signatures.include?(signature)

      seen_signatures << signature
      normalized_contact
    end
  end

  def normalized_contact(entry)
    hash = case entry
    when ActionController::Parameters
      entry.to_unsafe_h
    when Hash
      entry
    else
      nil
    end

    return unless hash

    hash = hash.stringify_keys
    name = hash["name"].to_s.squish.presence
    primary_phone = normalized_phone(hash["primary_phone"] || hash["phone"] || hash["location_phone"])
    secondary_phone = normalized_phone(hash["secondary_phone"])
    email = hash["email"].to_s.squish.presence
    website = hash["website"].to_s.squish.presence

    return if [name, primary_phone, secondary_phone, email, website].all?(&:blank?)

    {
      "name" => name,
      "primary_phone" => primary_phone,
      "secondary_phone" => secondary_phone,
      "email" => email,
      "website" => website
    }.compact
  end

  def normalized_phone(value)
    value.to_s.gsub(/[[:space:]]+/, " ").strip.presence
  end

  def phone_number_like?(value)
    value.to_s.gsub(/\D/, "").length >= 5
  end

  def contact_signature(contact)
    [
      contact["name"].to_s.downcase,
      sanitized_phone(contact["primary_phone"]),
      sanitized_phone(contact["secondary_phone"]),
      contact["email"].to_s.downcase,
      website_url_for(contact["website"]).to_s.downcase
    ].join("|")
  end

  def contact_fields_blank?(contact)
    contact["primary_phone"].blank? &&
      contact["secondary_phone"].blank? &&
      contact["email"].blank? &&
      contact["website"].blank?
  end

  def website_url_for(value)
    raw_value = value.to_s.squish
    return if raw_value.blank?

    candidate = raw_value.match?(/\Ahttps?:\/\//i) ? raw_value : "https://#{raw_value}"
    uri = URI.parse(candidate)
    return unless uri.is_a?(URI::HTTP) && uri.host.present?

    uri.to_s
  rescue URI::InvalidURIError
    nil
  end

  def email_href_for(value)
    email = value.to_s.squish
    return if email.blank?

    "mailto:#{email}"
  end

  def phone_href_for(value)
    sanitized = sanitized_phone(value)
    return if sanitized.blank?

    "tel:#{sanitized}"
  end

  def sanitized_phone(value)
    value.to_s.gsub(/[^\d+*#;,]/, "")
  end
end
