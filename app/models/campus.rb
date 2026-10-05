class Campus < ApplicationRecord
  belongs_to :parent, class_name: "Campus", optional: true
  has_many :campus_accesses, dependent: :destroy
  has_many :children, class_name: "Campus", foreign_key: :parent_id, dependent: :restrict_with_error
  scope :active, -> { where(active: true) }
  validates :active, inclusion: {in: [true, false]}
  validates :name, presence: true
  validates :rock_id, numericality: {only_integer: true, greater_than: 0}, uniqueness: true
  validate :acyclic_parent

  private

  def acyclic_parent
    seen = [id].compact
    ancestor = parent
    errors.add(:parent, "must be an existing campus") if parent_id.present? && ancestor.nil?
    while ancestor
      if seen.include?(ancestor.id)
        errors.add(:parent, "cannot form a cycle")
        break
      end
      seen << ancestor.id
      ancestor = ancestor.parent
    end
  end
end
