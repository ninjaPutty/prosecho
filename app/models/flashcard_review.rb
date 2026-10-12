class FlashcardReview < ApplicationRecord
  INTERVALS = [1, 3, 7, 14, 30, 60].freeze

  belongs_to :person_profile
  belongs_to :user

  def record_answer!(correct)
    self.level = correct ? [level + 1, INTERVALS.length].min : 0
    self.due_at = correct ? INTERVALS[level - 1].days.from_now : 10.minutes.from_now
    save!
  end
end
