class FlashcardRun < ApplicationRecord
  belongs_to :user
  has_many :cards, class_name: "FlashcardCard", dependent: :destroy

  validates :planned_count, numericality: {only_integer: true, in: 1..100}

  def completion
    (100.0 * cards.where.not(answered_at: nil).count / planned_count).round
  end

  def next_card
    cards.where(answered_at: nil).order(:position).first
  end
end
