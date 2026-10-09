class PersonChangeEvent < ApplicationRecord
  TYPES = %w[connection_status_changed home_address_changed family_composition_changed].freeze
  WINDOWS = [7, 14, 30, 90].freeze
  belongs_to :campus
  belongs_to :person_profile, optional: true
  belongs_to :previous_campus, class_name: "Campus"
  belongs_to :refresh_run, class_name: "PersonRefreshRun"
  validates :discovered_at, :policy_revision, :rock_guid, :source_system, presence: true
  validates :event_type, inclusion: {in: TYPES}

  def self.visible_to(actor, policy: DataPolicy.current)
    return none unless actor&.active? && !actor.access_locked? && actor.view_history? &&
      policy.persisted? && policy.confirmed? && policy.valid?

    grants = actor.campuses.active
    rock_ids = grants.pluck(:rock_id)
    return none if rock_ids.empty?
    scope = where(person_profile_id: PersonProfile.visible_to(actor, policy: policy).select(:id),
      campus_id: grants.select(:id), previous_campus_id: grants.select(:id),
      policy_revision: policy.revision)
    scope.where("event_type != ? OR household_reference_changed OR " \
      "related_campus_rock_ids && ARRAY[?]::integer[]", "family_composition_changed", rock_ids)
  end

  def readonly?
    persisted?
  end
end
