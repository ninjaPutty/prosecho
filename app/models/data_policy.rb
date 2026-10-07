require "yaml"

class DataPolicy < ApplicationRecord
  class Conflict < StandardError; end

  FIELD_LABELS = {
    "birth_date" => "Birth date (age filtering)",
    "connection_status" => "Connection status",
    "first_name" => "First name",
    "home_address" => "Primary home address and town",
    "household" => "Family membership and roles",
    "last_name" => "Last name",
    "marital_status" => "Marital status",
    "nick_name" => "Nickname / preferred name",
    "photo" => "Rock profile photo reference",
    "primary_campus" => "Primary campus"
  }.freeze
  MINIMUM_FIELDS = %w[first_name last_name primary_campus].freeze
  RETENTION_FIELDS = %i[backup_retention_days history_retention_days
    log_retention_days profile_retention_days].freeze
  TEXT_FIELDS = %i[address_handling address_source family_status_meaning
    household_handling household_source].freeze

  belongs_to :confirmed_by, class_name: "User", optional: true
  belongs_to :recorded_by, class_name: "User"
  before_validation :normalize_text

  validates(*RETENTION_FIELDS, numericality: {
    only_integer: true, greater_than: 0, less_than_or_equal_to: 2147483647, allow_nil: true
  })
  validates(*RETENTION_FIELDS, presence: true, if: :confirmed?)
  validates(*TEXT_FIELDS, length: {maximum: 4000})
  validates(*TEXT_FIELDS, presence: true, if: :confirmed?)
  validates :confirmed_at, :confirmed_by, presence: true, if: :confirmed?
  validates :retention_notes, length: {maximum: 5000}
  validates :slot, inclusion: {in: [1]}
  validates :status, inclusion: {in: %w[confirmed draft]}
  validate :valid_allowlists

  def self.current
    find_by(slot: 1) || new(default_attributes)
  end

  def self.default_attributes
    data = YAML.safe_load_file(Rails.root.join("config/pastoral.yml")).fetch("data")
    fields = RETENTION_FIELDS + TEXT_FIELDS + %i[attribute_keys retention_notes]
    data.slice(*fields.map(&:to_s)).symbolize_keys.merge(selected_fields: FIELD_LABELS.keys)
  end

  def apply_form_defaults
    return self if confirmed?

    # Suggestions belong to the edit form, not the persisted readiness decision.
    self.class.default_attributes.slice(*(RETENTION_FIELDS + TEXT_FIELDS)).each do |field, value|
      self[field] = value if self[field].blank?
    end
    self
  end

  def attribute_keys_text
    Array(attribute_keys).join("\n")
  end

  def attribute_keys_text=(value)
    self.attribute_keys = value.to_s.split(/[\r\n,]+/).map(&:strip).reject(&:blank?).uniq
  end

  def confirmed?
    status == "confirmed"
  end

  def decisions
    {
      "address_handling" => address_handling, "address_source" => address_source,
      "approved_at" => confirmed_at&.iso8601, "approved_by" => confirmed_by_id,
      "attribute_keys" => Array(attribute_keys).dup,
      "backup_retention_days" => backup_retention_days,
      "family_status_meaning" => family_status_meaning,
      "household_handling" => household_handling, "household_source" => household_source,
      "log_retention_days" => log_retention_days,
      "profile_retention_days" => profile_retention_days,
      "retention_days" => history_retention_days,
      "retention_notes" => retention_notes, "selected_fields" => Array(selected_fields).dup
    }
  end

  def revision
    persisted? ? "#{id}:#{lock_version}" : "new"
  end

  private

  def normalize_text
    (TEXT_FIELDS + [:retention_notes]).each do |field|
      self[field] = "" if self[field].nil?
    end
  end

  def valid_allowlists
    fields = selected_fields
    unless fields.is_a?(Array) && fields.uniq == fields && (fields - FIELD_LABELS.keys).empty?
      errors.add(:selected_fields, "must contain only the supported person fields")
    end
    if confirmed? && (MINIMUM_FIELDS - Array(fields)).any?
      errors.add(:selected_fields, "must include first name, last name, and primary campus")
    end
    keys = attribute_keys
    valid = keys.is_a?(Array) && keys.size <= 100 && keys.uniq == keys &&
      keys.all? { |key| key.is_a?(String) && key.match?(/\A[A-Za-z0-9_.:-]{1,100}\z/) }
    errors.add(:attribute_keys, "must contain up to 100 exact Rock attribute keys") unless valid
  end
end
