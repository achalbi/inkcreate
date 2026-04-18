require "cgi"

module LocatableRecord
  extend ActiveSupport::Concern

  LOCATION_SOURCES = %w[current search manual].freeze

  included do
    validate :locations_are_valid

    before_validation :normalize_locations_data
  end

  def locations
    normalize_location_collection(
      if location_data_source.present?
        location_data_source
      else
        legacy_location_collection
      end
    )
  end

  def locations_json
    locations.to_json
  end

  def locations_json=(value)
    @locations_json_input = value
  end

  def location_entries
    locations.map { |location| decorate_location(location) }
  end

  def location_count
    location_entries.size
  end

  def multiple_locations?
    location_count > 1
  end

  def location_present?
    location_count.positive?
  end

  def location_label
    primary_location&.dig(:label)
  end

  def location_secondary_line
    primary_location&.dig(:secondary_line)
  end

  def location_maps_url
    primary_location&.dig(:maps_url)
  end

  def location_count_label
    return if location_count.zero?
    return location_label if location_count == 1

    "#{location_count} locations"
  end

  def location_preview_text
    return if location_count.zero?
    return location_secondary_line.presence || location_label if location_count == 1

    "#{location_label} +#{location_count - 1} more"
  end

  private

  def primary_location
    location_entries.first
  end

  def decorate_location(location)
    label = location_label_for(location)

    {
      name: location["name"],
      address: location["address"],
      latitude: location["latitude"],
      longitude: location["longitude"],
      source: location["source"],
      label: label,
      secondary_line: location_secondary_line_for(location, label: label),
      maps_url: location_maps_url_for(location)
    }
  end

  def locations_are_valid
    locations.each_with_index do |location, index|
      prefix = location_count > 1 ? "Location #{index + 1}" : "Location"
      latitude = location["latitude"]
      longitude = location["longitude"]

      if location["source"].present? && !LOCATION_SOURCES.include?(location["source"])
        errors.add(:base, "#{prefix} source is invalid.")
      end

      next if latitude.blank? && longitude.blank?

      if latitude.blank? || longitude.blank?
        errors.add(:base, "#{prefix} coordinates must include both latitude and longitude.")
        next
      end

      unless latitude.to_f.between?(-90, 90)
        errors.add(:base, "#{prefix} latitude must be between -90 and 90.")
      end

      unless longitude.to_f.between?(-180, 180)
        errors.add(:base, "#{prefix} longitude must be between -180 and 180.")
      end
    end
  end

  def normalize_locations_data
    normalized_locations = normalize_location_collection(
      if locations_json_input_present?
        parse_locations_input(@locations_json_input)
      elsif location_data_source.present?
        location_data_source
      else
        legacy_location_collection
      end
    )

    write_locations_data(normalized_locations)
    sync_legacy_primary_location_fields(normalized_locations.first)
    clear_locations_json_input!
  end

  def location_data_source
    return unless has_attribute?(:locations_data)

    self[:locations_data]
  end

  def write_locations_data(locations)
    return unless has_attribute?(:locations_data)

    self[:locations_data] = locations
  end

  def locations_json_input_present?
    instance_variable_defined?(:@locations_json_input)
  end

  def clear_locations_json_input!
    remove_instance_variable(:@locations_json_input) if instance_variable_defined?(:@locations_json_input)
  end

  def parse_locations_input(value)
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

  def legacy_location_collection
    legacy_location = {
      "name" => self[:location_name],
      "address" => self[:location_address],
      "latitude" => self[:location_latitude],
      "longitude" => self[:location_longitude],
      "source" => self[:location_source]
    }

    normalize_location_collection([legacy_location])
  end

  def normalize_location_collection(collection)
    Array(collection).filter_map do |entry|
      normalized_location(entry)
    end
  end

  def normalized_location(entry)
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
    name = hash["name"].presence || hash["location_name"].presence
    address = hash["address"].presence || hash["location_address"].presence
    latitude = normalized_coordinate(hash["latitude"] || hash["location_latitude"])
    longitude = normalized_coordinate(hash["longitude"] || hash["location_longitude"])
    source = hash["source"].presence || hash["location_source"].presence

    name = name.to_s.squish.presence
    address = address.to_s.squish.presence
    source = source.to_s.presence_in(LOCATION_SOURCES)
    name = location_address_headline(address) if name.blank? && address.present?

    return if name.blank? && address.blank? && latitude.blank? && longitude.blank?

    {
      "name" => name,
      "address" => address,
      "latitude" => latitude,
      "longitude" => longitude,
      "source" => source
    }.compact
  end

  def normalized_coordinate(value)
    return if value.blank?

    Float(value)
  rescue ArgumentError, TypeError
    nil
  end

  def sync_legacy_primary_location_fields(primary_location)
    self[:location_name] = primary_location&.dig("name")
    self[:location_address] = primary_location&.dig("address")
    self[:location_latitude] = primary_location&.dig("latitude")
    self[:location_longitude] = primary_location&.dig("longitude")
    self[:location_source] = primary_location&.dig("source")
  end

  def location_label_for(location)
    location["name"].presence || location_address_headline(location["address"]).presence || location_coordinates_label_for(location)
  end

  def location_secondary_line_for(location, label: location_label_for(location))
    if location["address"].present? && location["address"] != label
      location["address"]
    elsif location_coordinates_present_for?(location) && location_coordinates_label_for(location) != label
      location_coordinates_label_for(location)
    end
  end

  def location_maps_url_for(location)
    query = if location_coordinates_present_for?(location)
      location_coordinates_label_for(location)
    else
      [location["name"], location["address"]].compact.join(" ")
    end

    return if query.blank?

    "https://www.google.com/maps/search/?api=1&query=#{CGI.escape(query)}"
  end

  def location_coordinates_label_for(location)
    return unless location_coordinates_present_for?(location)

    format("%.5f, %.5f", location["latitude"].to_f, location["longitude"].to_f)
  end

  def location_coordinates_present_for?(location)
    location["latitude"].present? && location["longitude"].present?
  end

  def location_address_headline(address)
    address.to_s.split(",").first.to_s.squish.presence
  end
end
