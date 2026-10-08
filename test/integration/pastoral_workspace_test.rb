require "test_helper"
require "minitest/mock"
require_relative "../support/directory_policy"

class PastoralWorkspaceTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include DirectoryPolicy

  setup do
    @policy = confirm_directory_policy
    PersonProfile.update_all(policy_revision: @policy.revision)
    sign_in users(:staff)
  end

  test "workspace shows authorized persisted people and all requested filters" do
    get dashboard_path
    assert_response :success
    assert_select "h1", "People at a glance"
    assert_includes response.body, "Alex Example"
    assert_not response.body.include?("Outside Example")
    assert_select "select[name='filters[campus_id]']"
    assert_select "select[name='filters[connection_status]']"
    assert_select "select[name='filters[town]']"
    assert_select "input[name='filters[min_age]']"
    assert_select "input[name='filters[max_age]']"
    assert_includes response.headers["Cache-Control"], "no-store"
  end

  test "combined filters live in the session and result pagination does not expose names or towns" do
    post workspace_filters_path, params: {filters: {
      campus_id: campuses(:north).id, connection_status: "201", min_age: "30", max_age: "50",
      town: "Example Town", search: "Alex"
    }}
    assert_redirected_to dashboard_path
    assert_not response.headers["Location"].include?("Example")
    follow_redirect!
    assert_includes response.body, "Alex Example"
    assert_not response.body.include?("Casey Example")
    delete workspace_filters_path
    follow_redirect!
    assert_includes response.body, "Casey Example"
  end

  test "profile details and photo endpoints enforce scope and precise-address permissions" do
    person = person_profiles(:alex)
    get workspace_person_path(person)
    assert_response :success
    assert_includes response.body, "Example Town"
    assert_not response.body.include?("10 Fixture Lane")
    assert_select "turbo-frame#person_details"
    get workspace_person_path(person_profiles(:outside))
    assert_response :not_found
    users(:staff).update!(view_photos: false)
    get workspace_person_photo_path(person)
    assert_response :forbidden
  end

  test "allowed photos are served privately without exposing the Rock credential" do
    result = Integrations::Rock::ReadClient::Photo.new(body: "fixture-image".b, content_type: "image/png")
    client = Object.new
    client.define_singleton_method(:photo) { |_| result }
    Integrations::Rock::ReadClient.stub(:new, client) do
      get workspace_person_photo_path(person_profiles(:alex))
    end
    assert_response :success
    assert_equal "image/png", response.media_type
    assert_includes response.headers["Cache-Control"], "no-store"
    assert_equal "fixture-image", response.body
  end

  test "draft or changed data policy does not expose old cached people" do
    @policy.update!(status: "draft", confirmed_at: nil, confirmed_by: nil)
    get dashboard_path
    assert_response :success
    assert_not response.body.include?("Alex Example")
    assert_includes response.body, "Data decisions"
  end

  test "refresh is a deliberate authenticated POST that enqueues durable work" do
    assert_enqueued_with(job: PersonRefreshJob) do
      post workspace_refresh_path
    end
    assert_redirected_to dashboard_path
    run = PersonRefreshRun.order(:created_at).last
    assert_equal users(:staff).id, run.actor_id
    assert_equal [campuses(:north).id], run.campus_ids
    assert_equal @policy.revision, run.policy_revision
  end

  test "clicking refresh resumes an orphaned run instead of creating a second run" do
    run = PersonRefreshRun.start!(actor: users(:staff))
    run.update!(status: "running", page_count: 2, next_offset: 100)
    assert_no_difference "PersonRefreshRun.count" do
      assert_enqueued_with(job: PersonRefreshJob, args: [run.id]) do
        post workspace_refresh_path
      end
    end
    assert_redirected_to dashboard_path
    assert_equal 100, run.reload.next_offset
    follow_redirect!
    assert_select "button", "Resume/check refresh"
    assert_select "[data-refresh-progress][data-status-url]"
    get workspace_refresh_status_path
    assert_response :success
    assert_equal 2, response.parsed_body["page_count"]
    assert_equal "running", response.parsed_body["status"]
    assert_includes response.headers["Cache-Control"], "no-store"
  end

  test "a refresh POST actually executes the reader and publishes when the worker performs it" do
    batch = Integrations::Rock::PeopleReader::Page.new(people: [], offset: 0,
      limit: 50, next_offset: nil, policy_revision: @policy.revision, observed_at: Time.current)
    reader = Object.new
    reader.define_singleton_method(:read_page) { |**_| batch }
    Integrations::Rock::PeopleReader.stub(:new, reader) do
      perform_enqueued_jobs(only: PersonRefreshJob) { post workspace_refresh_path }
    end
    assert_redirected_to dashboard_path
    run = PersonRefreshRun.order(:created_at).last
    assert_equal "succeeded", run.status
    assert_equal 1, run.page_count
  end

  test "failed refresh shows actionable safe diagnostics and explicitly resumes the same checkpoint" do
    run = PersonRefreshRun.start!(actor: users(:staff))
    run.update!(status: "failed", page_count: 2, next_offset: 100, last_rock_id: 500,
      error_code: "invalid_person_identity",
      error_details: {"phase" => "read", "page" => 3, "rock_id" => 501, "fields" => ["Guid"]})
    get dashboard_path
    assert_response :success
    assert_select "[role='alert']", text: /invalid identity/
    assert_includes response.body, "Rock record ID: 501"
    assert_includes response.body, "2 pages and 0 records retained"
    assert_select "button", "Retry from saved checkpoint"
    assert_select "input[name='resume_run_id'][value='#{run.id}']"
    get workspace_refresh_status_path
    assert_equal "read", response.parsed_body.dig("error_details", "phase")
    assert_equal true, response.parsed_body["resumable"]
    assert_no_difference "PersonRefreshRun.count" do
      assert_enqueued_with(job: PersonRefreshJob, args: [run.id]) do
        post workspace_refresh_path, params: {resume_run_id: run.id}
      end
    end
    assert_redirected_to dashboard_path
    assert_equal "queued", run.reload.status
    assert_equal 500, run.last_rock_id
  end

  test "resume POST cannot target another actor or bypass a changed policy" do
    run = PersonRefreshRun.start!(actor: users(:staff))
    run.update!(status: "failed", error_code: "invalid_person_identity",
      error_details: {"rock_id" => 501, "last_rock_id" => 500, "phase" => "read"})
    sign_in users(:administrator)
    users(:administrator).campuses << campuses(:north)
    assert_no_enqueued_jobs do
      post workspace_refresh_path, params: {resume_run_id: run.id}
    end
    assert_response :not_found
    sign_in users(:staff)
    @policy.update!(history_retention_days: 180)
    assert_no_enqueued_jobs do
      post workspace_refresh_path, params: {resume_run_id: run.id}
    end
    assert_redirected_to dashboard_path
    assert_equal "failed", run.reload.status
    get workspace_refresh_status_path
    assert_not response.parsed_body["resumable"]
    assert_nil response.parsed_body.dig("error_details", "rock_id")
    assert_nil response.parsed_body.dig("error_details", "last_rock_id")
  end

  test "Turbo profile responses contain only the detail frame and maintain current permissions" do
    get workspace_person_path(person_profiles(:alex)), headers: {"Turbo-Frame" => "person_details"}
    assert_response :success
    assert_not response.body.include?("<html")
    assert_select "turbo-frame#person_details"
    assert_not response.body.include?("10 Fixture Lane")
    users(:staff).update!(view_locations: true)
    get workspace_person_path(person_profiles(:alex)), headers: {"Turbo-Frame" => "person_details"}
    assert_includes response.body, "10 Fixture Lane"
  end

  test "map and change views explain real setup state rather than presenting fake data" do
    get workspace_map_path
    assert_response :success
    assert_includes response.body, "Private map setup"
    get workspace_changes_path
    assert_response :success
    assert_includes response.body, "Change history setup"
  end

  test "invalid age ranges and forged campuses cannot broaden directory access" do
    post workspace_filters_path, params: {filters: {min_age: "50", max_age: "20"}}
    assert_response :unprocessable_content
    assert_not response.body.include?("Alex Example")
    post workspace_filters_path, params: {filters: {campus_id: campuses(:south).id}}
    assert_response :unprocessable_content
    assert_not response.body.include?("Outside Example")
  end
end
