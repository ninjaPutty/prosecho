class CreateFlashcardPractice < ActiveRecord::Migration[8.1]
  def change
    create_table :flashcard_runs, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.string :campus_ids, array: true, null: false, default: []
      t.string :status_ids, array: true, null: false, default: []
      t.integer :planned_count, null: false
      t.timestamps
    end

    create_table :flashcard_cards, id: :uuid do |t|
      t.references :flashcard_run, type: :uuid, null: false, foreign_key: true
      t.references :person_profile, type: :uuid, foreign_key: {on_delete: :nullify}
      t.uuid :option_ids, array: true, null: false, default: []
      t.integer :position, null: false
      t.datetime :answered_at
      t.boolean :correct
      t.timestamps
    end
    add_index :flashcard_cards, [:flashcard_run_id, :position], unique: true

    create_table :flashcard_reviews, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.references :person_profile, type: :uuid, null: false,
        foreign_key: {on_delete: :cascade}
      t.integer :level, null: false, default: 0
      t.datetime :due_at, null: false
      t.timestamps
    end
    add_index :flashcard_reviews, [:user_id, :person_profile_id], unique: true
  end
end
