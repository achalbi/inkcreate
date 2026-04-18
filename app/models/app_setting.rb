class AppSetting < ApplicationRecord
  OCR_MODES = %w[manual].freeze
  BACKUP_PROVIDERS = %w[google_drive].freeze
  CAPTURE_QUALITY_PROFILES = {
    "optimized" => {
      "label" => "Optimized",
      "description" => "Balanced default. Shrinks very large captures to 1800 px on the long edge and uses stronger compression to keep files smaller.",
      "max_dimension" => 1800,
      "jpeg_quality" => 0.8,
      "video_width" => 2048,
      "video_height" => 1536
    },
    "high" => {
      "label" => "High",
      "description" => "Prioritizes readability for handwriting and diagrams. Keeps up to 2500 px on the long edge with lighter compression for cleaner detail.",
      "max_dimension" => 2500,
      "jpeg_quality" => 0.9,
      "video_width" => 2560,
      "video_height" => 1920
    },
    "original" => {
      "label" => "Original",
      "description" => "Preserves the full browser-provided image size whenever possible. Largest files, but the most source detail.",
      "max_dimension" => nil,
      "jpeg_quality" => 0.98,
      "video_width" => 2560,
      "video_height" => 1920
    }
  }.freeze
  IMAGE_QUALITY_DEFAULTS = {
    "capture_quality_preset" => "optimized"
  }.freeze
  WORKSPACE_LAUNCHER_IDLE_TIMEOUT_OPTIONS = [
    ["1 minute", 60_000],
    ["3 minutes", 180_000],
    ["9 minutes", 540_000],
    ["25 minutes", 1_500_000],
    ["1 hour", 3_600_000],
    ["7 hours", 25_200_000],
    ["11 hours", 39_600_000],
    ["23 hours", 82_800_000]
  ].freeze
  WORKSPACE_LAUNCHER_CONTINUE_SCOPES = %w[today latest].freeze
  WORKSPACE_LAUNCHER_DEFAULTS = {
    "enabled" => true,
    "idle_timeout_ms" => WORKSPACE_LAUNCHER_IDLE_TIMEOUT_OPTIONS.first.last,
    "continue_scope" => "today"
  }.freeze
  PRIVACY_DEFAULTS = {
    "allow_ocr_processing" => true,
    "include_photos_in_backups" => true,
    "keep_deleted_chapters_recoverable" => true,
    "clear_backup_metadata_on_disconnect" => true
  }.freeze

  belongs_to :user

  before_validation :normalize_privacy_options!
  before_validation :normalize_image_quality_preferences!
  before_validation :normalize_launcher_preferences!

  validates :ocr_mode, inclusion: { in: OCR_MODES }
  validates :backup_provider, inclusion: { in: BACKUP_PROVIDERS }, allow_blank: true
  validates :capture_quality_preset, inclusion: { in: CAPTURE_QUALITY_PROFILES.keys }
  validates :workspace_launcher_idle_timeout_ms, inclusion: {
    in: WORKSPACE_LAUNCHER_IDLE_TIMEOUT_OPTIONS.map(&:last)
  }

  def google_drive_backup?
    backup_enabled? && backup_provider == "google_drive"
  end

  def merged_privacy_options
    PRIVACY_DEFAULTS.merge(privacy_options.to_h.stringify_keys.slice(*PRIVACY_DEFAULTS.keys))
  end

  def merged_image_quality_preferences
    IMAGE_QUALITY_DEFAULTS.merge(image_quality_preferences.to_h.stringify_keys.slice(*IMAGE_QUALITY_DEFAULTS.keys))
  end

  def merged_launcher_preferences
    WORKSPACE_LAUNCHER_DEFAULTS.merge(raw_launcher_preferences.slice(*WORKSPACE_LAUNCHER_DEFAULTS.keys))
  end

  def capture_quality_preset
    merged_image_quality_preferences.fetch("capture_quality_preset")
  end

  def capture_quality_preset=(value)
    self.image_quality_preferences = image_quality_preferences.to_h.stringify_keys.merge("capture_quality_preset" => value)
  end

  def capture_quality_profile
    CAPTURE_QUALITY_PROFILES.fetch(capture_quality_preset)
  end

  def workspace_launcher_enabled?
    ActiveModel::Type::Boolean.new.cast(merged_launcher_preferences.fetch("enabled"))
  end

  def workspace_launcher_enabled=(value)
    return unless launcher_preferences_supported?

    self[:launcher_preferences] = raw_launcher_preferences.merge("enabled" => value)
  end

  def workspace_launcher_idle_timeout_ms
    merged_launcher_preferences.fetch("idle_timeout_ms")
  end

  def workspace_launcher_idle_timeout_ms=(value)
    return unless launcher_preferences_supported?

    self[:launcher_preferences] = raw_launcher_preferences.merge("idle_timeout_ms" => value)
  end

  def workspace_launcher_continue_scope
    merged_launcher_preferences.fetch("continue_scope")
  end

  def workspace_launcher_continue_scope=(value)
    return unless launcher_preferences_supported?

    self[:launcher_preferences] = raw_launcher_preferences.merge("continue_scope" => value)
  end

  def launcher_preferences_supported?
    has_attribute?("launcher_preferences")
  end

  def allow_ocr_processing?
    privacy_option_enabled?("allow_ocr_processing")
  end

  def include_photos_in_backups?
    privacy_option_enabled?("include_photos_in_backups")
  end

  def include_media_in_backups?
    include_photos_in_backups?
  end

  def keep_deleted_chapters_recoverable?
    privacy_option_enabled?("keep_deleted_chapters_recoverable")
  end

  def clear_backup_metadata_on_disconnect?
    privacy_option_enabled?("clear_backup_metadata_on_disconnect")
  end

  private

  def normalize_privacy_options!
    raw_options = privacy_options.to_h.stringify_keys

    self.privacy_options = PRIVACY_DEFAULTS.keys.index_with do |key|
      if raw_options.key?(key)
        ActiveModel::Type::Boolean.new.cast(raw_options[key])
      else
        PRIVACY_DEFAULTS.fetch(key)
      end
    end
  end

  def normalize_image_quality_preferences!
    raw_options = image_quality_preferences.to_h.stringify_keys
    preset = raw_options["capture_quality_preset"].presence_in(CAPTURE_QUALITY_PROFILES.keys) ||
      IMAGE_QUALITY_DEFAULTS.fetch("capture_quality_preset")

    self.image_quality_preferences = {
      "capture_quality_preset" => preset
    }
  end

  def normalize_launcher_preferences!
    return unless launcher_preferences_supported?

    raw_options = raw_launcher_preferences
    enabled = if raw_options.key?("enabled")
      ActiveModel::Type::Boolean.new.cast(raw_options["enabled"])
    else
      WORKSPACE_LAUNCHER_DEFAULTS.fetch("enabled")
    end
    idle_timeout_ms = raw_options["idle_timeout_ms"].to_i
    idle_timeout_ms = WORKSPACE_LAUNCHER_DEFAULTS.fetch("idle_timeout_ms") unless
      WORKSPACE_LAUNCHER_IDLE_TIMEOUT_OPTIONS.map(&:last).include?(idle_timeout_ms)

    continue_scope = raw_options["continue_scope"].to_s.presence_in(WORKSPACE_LAUNCHER_CONTINUE_SCOPES) ||
      WORKSPACE_LAUNCHER_DEFAULTS.fetch("continue_scope")

    self[:launcher_preferences] = {
      "enabled" => enabled,
      "idle_timeout_ms" => idle_timeout_ms,
      "continue_scope" => continue_scope
    }
  end

  def privacy_option_enabled?(key)
    ActiveModel::Type::Boolean.new.cast(merged_privacy_options.fetch(key))
  end

  def raw_launcher_preferences
    return {} unless launcher_preferences_supported?

    self[:launcher_preferences].to_h.stringify_keys
  end
end
