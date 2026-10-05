class CampusAccess < ApplicationRecord
  belongs_to :campus
  belongs_to :user
  validates :campus_id, uniqueness: {scope: :user_id}
end
