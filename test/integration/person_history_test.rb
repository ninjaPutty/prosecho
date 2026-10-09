require "test_helper"
require_relative "../support/directory_policy"

class PersonHistoryTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include DirectoryPolicy

  setup do
    @policy = confirm_directory_policy
    @actor = users(:staff)
    @actor.update!(view_history: true)
    PersonProfile.update_all(policy_revision: @policy.revision)
    @run = PersonRefreshRun.start!(actor: users(:administrator))
    @run.update!(status: "succeeded", finished_at: Time.current)
    sign_in @actor
  end

  def event(person: person_profiles(:alex), type: "connection_status_changed", at: Time.current, **extra)
    PersonChangeEvent.create!(person_profile: person, refresh_run: @run,
      campus: person.campus, previous_campus: person.campus,
      source_system: person.source_system, rock_guid: person.rock_guid, rock_id: person.rock_id,
      policy_revision: @policy.revision, event_type: type,
      previous_value: {"label" => "Old Example"}, current_value: {"label" => "New Example"},
      discovered_at: at, **extra)
  end

  test "feed uses discovery windows and shared filters without exposing private filter values in URLs" do
    event(at: 5.days.ago)
    second_run = PersonRefreshRun.start!(actor: users(:administrator))
    event(at: 20.days.ago, refresh_run: second_run)
    event(person: person_profiles(:outside))
    get workspace_changes_path
    assert_response :success
    assert_includes response.body, "2 discovered changes"
    assert_not_includes response.body, "Outside Example"
    post workspace_filters_path, params: {view: "changes", filters: {
      change_days: "7", search: "Alex", town: "Example Town", min_age: "30", max_age: "50"
    }}
    assert_redirected_to workspace_changes_path
    assert_not_includes response.headers["Location"], "Example"
    follow_redirect!
    assert_includes response.body, "1 discovered changes"
    get dashboard_path
    assert_includes response.body, "Alex Example"
    assert_not_includes response.body, "Casey Example"
  end

  test "history and current and historical campus boundaries cannot be bypassed" do
    event(previous_campus: campuses(:south))
    get workspace_changes_path
    assert_response :success
    assert_includes response.body, "0 discovered changes"
    @actor.update!(view_history: false)
    get workspace_changes_path
    assert_response :forbidden
    assert AccessEvent.exists?(actor: @actor, resource: "history", outcome: "denied")
    sign_out @actor
    get workspace_changes_path
    assert_redirected_to new_user_session_path
  end

  test "precise prior and current addresses require location permission" do
    event(type: "home_address_changed",
      previous_value: {"status" => "known", "city" => "Example Town", "street1" => "10 Fixture Lane"},
      current_value: {"status" => "known", "city" => "New Example Town", "street1" => "20 Fixture Lane"})
    get workspace_changes_path
    assert_includes response.body, "New Example Town"
    assert_not_includes response.body, "Fixture Lane"
    @actor.update!(view_locations: true)
    get workspace_changes_path
    assert_includes response.body, "10 Fixture Lane"
    assert_includes response.body, "20 Fixture Lane"
  end

  test "household changes outside the viewer's member campus scope stay hidden" do
    event(type: "family_composition_changed", related_campus_rock_ids: [100002],
      details: {"added" => [{"campus_rock_id" => 100002, "person_guid" => "private-outside-guid"}]})
    get workspace_changes_path
    assert_includes response.body, "0 discovered changes"
    assert_not_includes response.body, "private-outside-guid"
  end

  test "invalid discovery windows do not broaden results" do
    event
    post workspace_filters_path, params: {view: "changes", filters: {change_days: "365"}}
    assert_response :unprocessable_content
    assert_includes response.body, "Choose a discovery window"
  end

  test "a changed policy hides previous history rather than exposing fields from an older allowlist" do
    event
    @policy.update!(history_retention_days: 180)
    get workspace_changes_path
    assert_response :success
    assert_includes response.body, "0 discovered changes"
    assert_not_includes response.body, "Old Example"
  end

  test "directory SQL logging redacts private name and town filter values" do
    person_profiles(:alex).update!(city: "synthetic-private-town")
    output = StringIO.new
    original_logger = ActiveRecord::Base.logger
    ActiveRecord::Base.logger = ActiveSupport::Logger.new(output)
    Directory::Query.new(actor: @actor, filters: {search: "synthetic-private-search",
                                                  town: "synthetic-private-town", min_age: "30", max_age: "50"})
    assert_not output.string.include?("synthetic-private-search"), "Private name filter leaked to SQL logging"
    assert_not output.string.include?("synthetic-private-town"), "Private town filter leaked to SQL logging"
  ensure
    ActiveRecord::Base.logger = original_logger
  end
end
