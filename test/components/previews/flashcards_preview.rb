class FlashcardsPreview < Lookbook::Preview
  def complete
    run = FlashcardRun.new(id: "00000000-0000-4000-8000-000000000001", planned_count: 10)
    run.define_singleton_method(:completion) { 100 }
    cards = Object.new
    cards.define_singleton_method(:where) { |**| Array.new(8) }
    run.define_singleton_method(:cards) { cards }
    render Components::Workspace::Flashcards.new(actor: User.new(view_photos: true),
      practice: nil, run: run)
  end

  def daily_progress
    render Components::Workspace::FlashcardSummary.new(days: [
      {day: Date.new(2026, 10, 12), runs: 2, attempted: 15, completion: 75, accuracy: 80},
      {day: Date.new(2026, 10, 11), runs: 1, attempted: 10, completion: 100, accuracy: 70}
    ])
  end
end
