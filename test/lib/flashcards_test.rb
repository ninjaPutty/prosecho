require "test_helper"
require_relative "../support/directory_policy"

class FlashcardSelectionTest < ActiveSupport::TestCase
  include DirectoryPolicy

  setup do
    @policy = confirm_directory_policy
    @actor = users(:staff)
    @practice = Directory::Flashcards.new(actor: @actor)
    @people = 4.times.map do |index|
      PersonProfile.create!(campus: campuses(:north), source_system: "rock.chapel.org",
        rock_guid: SecureRandom.uuid, rock_id: 600 + index, display_name: "Fixture #{index}",
        photo_id: 50 + index, connection_status_id: 201,
        policy_revision: @policy.revision, observed_at: Time.current)
    end
  end

  test "overdue reviews precede new people and future reviews" do
    FlashcardReview.create!(user: @actor, person_profile: @people.first, due_at: 1.hour.ago, level: 0)
    run = start_run
    assert_equal @people.first.id, run.next_card.person_profile_id
    assert_equal 4, @practice.choices_for(run, run.next_card).map(&:display_name).uniq.length
  end

  test "misses reset spacing and correct answers lengthen intervals" do
    run = start_run
    card = run.next_card
    wrong = card.option_ids.find { |id| id != card.person_profile_id }
    @practice.answer!(run: run, card: card, option_id: wrong)
    review = FlashcardReview.find_by!(user: @actor, person_profile: card.person_profile)
    assert_equal 0, review.level
    assert_in_delta 10.minutes.from_now, review.due_at, 1
    review.record_answer!(true)
    assert_equal 1, review.level
    assert_in_delta 1.day.from_now, review.due_at, 1
    review.record_answer!(true)
    assert_equal 2, review.level
    assert_in_delta 3.days.from_now, review.due_at, 1
  end

  test "pools without four distinct names are rejected without saving a run" do
    @people.last.update!(photo_id: nil)
    assert_no_difference "FlashcardRun.count" do
      assert_raises(Directory::Flashcards::Invalid) { start_run }
    end
  end

  test "same gender options are preferred only from the approved pool" do
    @policy.update!(attribute_keys: ["Gender"])
    @people.each { |person| person.update!(policy_revision: @policy.revision, custom_attributes: {"Gender" => "A"}) }
    @people.last.update!(custom_attributes: {"Gender" => "B"})
    extra = PersonProfile.create!(campus: campuses(:north), source_system: "rock.chapel.org",
      rock_guid: SecureRandom.uuid, rock_id: 700, display_name: "Extra Fixture", photo_id: 99,
      connection_status_id: 201, policy_revision: @policy.revision, observed_at: Time.current,
      custom_attributes: {"Gender" => "A"})
    @practice = Directory::Flashcards.new(actor: @actor)
    FlashcardReview.create!(user: @actor, person_profile: @people.first, due_at: 1.hour.ago)
    run = start_run
    choices = @practice.choices_for(run, run.next_card)
    assert_equal ["A"], choices.map { |person| person.custom_attributes["Gender"] }.uniq
    assert_includes choices.map(&:id), extra.id
  end

  test "revoked choice photos block both display and scoring" do
    run = start_run
    card = run.next_card
    PersonProfile.find(card.option_ids.last).update!(photo_id: nil)
    assert_raises(Directory::Flashcards::Invalid) { @practice.choices_for(run, card) }
    assert_raises(Directory::Flashcards::Invalid) do
      @practice.answer!(run: run, card: card, option_id: card.person_profile_id)
    end
    assert_equal 0, run.completion
  end

  test "daily summaries isolate users and preserve local calendar boundaries" do
    travel_to(Time.zone.local(2026, 10, 11, 23, 59)) { start_run }
    travel_to(Time.zone.local(2026, 10, 12, 0, 1)) { start_run }
    summary = @practice.summary
    assert_equal [Date.new(2026, 10, 12), Date.new(2026, 10, 11)], summary.map { |day| day[:day] }
    assert_equal [1, 1], summary.map { |day| day[:runs] }
    assert_empty Directory::Flashcards.new(actor: users(:administrator)).summary
  end

  private

  def start_run
    @practice.start!(campus_ids: [campuses(:north).id], status_ids: ["201"], count: 1)
  end
end
