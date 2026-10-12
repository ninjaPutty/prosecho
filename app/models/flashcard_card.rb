class FlashcardCard < ApplicationRecord
  belongs_to :flashcard_run
  belongs_to :person_profile, optional: true
end
