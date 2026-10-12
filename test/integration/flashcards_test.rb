require "test_helper"
require_relative "../support/directory_policy"

class FlashcardsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include DirectoryPolicy

  setup do
    @policy = confirm_directory_policy
    @actor = users(:staff)
    @campus = campuses(:north)
    PersonProfile.update_all(policy_revision: @policy.revision)
    @people = 5.times.map do |index|
      PersonProfile.create!(campus: @campus, source_system: "rock.chapel.org",
        rock_guid: SecureRandom.uuid, rock_id: 500 + index, first_name: "Example#{index}",
        last_name: "Fixture", display_name: "Example#{index} Fixture", photo_id: 50 + index,
        connection_status_id: 201, connection_status_label: "Connected",
        policy_revision: @policy.revision, observed_at: Time.current)
    end
    sign_in @actor
  end

  test "photo permission gates the menu and every practice action" do
    get dashboard_path
    assert_select "a[href=?]", workspace_flashcards_path
    get workspace_flashcards_path
    assert_response :success
    assert_select "input[name='practice[campus_ids][]'][value=?]", @campus.id
    assert_select "input[value=?]", campuses(:south).id, count: 0
    @actor.update!(view_photos: false)
    get dashboard_path
    assert_select "a[href=?]", workspace_flashcards_path, count: 0
    get workspace_flashcards_path
    assert_response :forbidden
    assert_no_difference "FlashcardRun.count" do
      start_run
      assert_response :forbidden
    end
  end

  test "cards show four names then reveal the answer and aggregate multiple runs" do
    start_run(count: 2)
    run = @actor.flashcard_runs.order(:created_at).last
    assert_redirected_to workspace_flashcard_path(run)
    card = run.next_card
    follow_redirect!
    assert_select "button[name=option_id]", 4
    assert_select "img[alt=?]", "Who is this person?", count: 1
    assert_not_includes response.body, "This is #{card.person_profile.display_name}."
    post answer_workspace_flashcard_path(run), params: {card_id: card.id, option_id: card.person_profile_id}
    follow_redirect!
    assert_includes response.body, "Correct!"
    assert_includes response.body, "This is #{card.person_profile.display_name}."
    assert_equal 50, run.completion
    assert_equal 1, FlashcardReview.find_by!(user: @actor, person_profile: card.person_profile).level
    assert_no_difference "FlashcardReview.count" do
      post answer_workspace_flashcard_path(run), params: {card_id: card.id, option_id: card.person_profile_id}
    end
    assert_equal 1, run.cards.where.not(answered_at: nil).count
    start_run(count: 2)
    get dashboard_path
    assert_includes response.body, "1 people tried across 2 runs"
    assert_includes response.body, "25% complete / 100% correct"
  end

  test "forged scopes and other users runs are rejected" do
    assert_no_difference "FlashcardRun.count" do
      start_run(campus_ids: [campuses(:south).id])
      assert_response :unprocessable_content
      start_run(status_ids: ["999999"])
      assert_response :unprocessable_content
      start_run(count: 101)
      assert_response :unprocessable_content
    end
    start_run
    run = @actor.flashcard_runs.order(:created_at).last
    sign_in users(:administrator)
    users(:administrator).update!(view_photos: true)
    CampusAccess.create!(user: users(:administrator), campus: @campus)
    get workspace_flashcard_path(run)
    assert_response :not_found
    sign_in users(:administrator)
    post answer_workspace_flashcard_path(run), params: {card_id: run.next_card.id,
                                                        option_id: run.next_card.person_profile_id}
    assert_response :not_found
  end

  test "daily dashboard summaries are separate full width banners" do
    start_run
    @actor.flashcard_runs.order(:created_at).last.update!(created_at: 1.day.ago)
    start_run

    get dashboard_path
    assert_response :success
    assert_select "section[aria-label='Flashcard practice']" do
      assert_select "article.w-full", count: 2
      assert_select "article h2", count: 2
      assert_select "[class*='grid-cols']", count: 0
      assert_select "p", text: "0 people tried across 1 runs", count: 2
    end
  end

  test "revoked campus or policy access hides saved choices" do
    start_run
    run = @actor.flashcard_runs.order(:created_at).last
    @policy.update!(status: "draft")
    get workspace_flashcard_path(run)
    assert_response :forbidden
  end

  test "photo revocation blocks saved runs and answer submissions" do
    start_run
    run = @actor.flashcard_runs.order(:created_at).last
    card = run.next_card
    @actor.update!(view_photos: false)
    get workspace_flashcard_path(run)
    assert_response :forbidden
    post answer_workspace_flashcard_path(run), params: {card_id: card.id,
                                                        option_id: card.person_profile_id}
    assert_response :forbidden
    assert_nil card.reload.answered_at
  end

  test "practice mutations require CSRF protection" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    assert_no_difference "FlashcardRun.count" do
      start_run
      assert_response :unprocessable_content
    end
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  test "unlisted answers do not alter progress" do
    start_run
    run = @actor.flashcard_runs.order(:created_at).last
    post answer_workspace_flashcard_path(run), params: {card_id: run.next_card.id,
                                                        option_id: person_profiles(:outside).id}
    assert_redirected_to workspace_flashcards_path
    assert_equal 0, run.completion
    assert_equal 0, FlashcardReview.count
  end

  private

  def start_run(count: 1, campus_ids: [@campus.id], status_ids: ["201"])
    post workspace_flashcards_path, params: {practice: {count: count,
                                                        campus_ids: campus_ids, status_ids: status_ids}}
  end
end
