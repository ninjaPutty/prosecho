class AccessEvent < ApplicationRecord
  belongs_to :actor, class_name: "User"
  validates :outcome, inclusion: {in: %w[allowed denied provisioned revoked updated]}
  validates :resource, inclusion: {in: %w[account administration campus campus_access
    church_next_accounts dashboard data_policy directory flashcards history locations photos]}
end
