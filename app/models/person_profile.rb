class PersonProfile < ApplicationRecord
  belongs_to :campus
  validates :display_name, :observed_at, :policy_revision, :rock_guid, presence: true
  validates :rock_id, numericality: {only_integer: true, greater_than: 0}
  validates :rock_guid, uniqueness: {scope: :source_system}

  def self.visible_to(actor, policy: DataPolicy.current)
    return none unless actor&.active? && !actor.access_locked? &&
      policy.persisted? && policy.confirmed? && policy.valid?

    where(campus_id: actor.campuses.active.select(:id), policy_revision: policy.revision,
      in_population: true)
  end

  def age(today: Date.current)
    return nil unless birth_date && birth_date <= today
    before_birthday = ([today.month, today.day] <=> [birth_date.month, birth_date.day]).negative?
    today.year - birth_date.year - (before_birthday ? 1 : 0)
  end

  def initials
    [first_name, last_name].filter_map { |value| value&.first }.join.upcase.presence || "?"
  end
end
