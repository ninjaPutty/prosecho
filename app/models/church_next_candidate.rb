class ChurchNextCandidate < ApplicationRecord
  belongs_to :church_next_account
  belongs_to :person_profile, optional: true
  belongs_to :reviewed_by, class_name: "User", optional: true

  validates :policy_revision, :rock_guid, presence: true
  validates :reason, inclusion: {in: %w[email name]}
  validates :score, numericality: {only_integer: true, in: 0..100}
  validates :status, inclusion: {in: %w[matched pending rejected]}

  def self.visible_to(actor, policy: DataPolicy.current)
    return none unless actor&.administrator? && policy.selected_fields.include?("email")

    where(person_profile_id: PersonProfile.visible_to(actor, policy: policy).select(:id),
      policy_revision: policy.revision)
  end
end
