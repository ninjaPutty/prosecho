class PersonSnapshot < ApplicationRecord
  belongs_to :campus
  belongs_to :person_profile
  belongs_to :refresh_run, class_name: "PersonRefreshRun"
  validates :observed_at, :policy_revision, presence: true
end
