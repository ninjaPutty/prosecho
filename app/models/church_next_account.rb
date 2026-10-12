class ChurchNextAccount < ApplicationRecord
  belongs_to :person_profile, optional: true
  has_many :candidates, class_name: "ChurchNextCandidate", dependent: :destroy
  has_one :link_delivery, class_name: "ChurchNextLinkDelivery", dependent: :destroy

  validates :email, :first_name, :last_name, presence: true
  validates :email, length: {maximum: 254}
  validates :email_verified, :photo_available, inclusion: {in: [true, false]}
  validates :external_user_id, format: {with: /\A[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}\z/},
    uniqueness: true
  validates :first_name, :last_name, length: {maximum: 200}
  validates :status, inclusion: {in: %w[linked pending]}

  def display_name
    "#{first_name} #{last_name}"
  end

  def linked?
    status == "linked"
  end
end
