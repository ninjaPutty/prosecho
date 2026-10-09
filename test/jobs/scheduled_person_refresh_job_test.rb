require "test_helper"
require "minitest/mock"
require_relative "../support/directory_policy"

class ScheduledPersonRefreshJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include DirectoryPolicy

  setup do
    confirm_directory_policy
    @schedule = SyncSchedule.create!(administrator: users(:administrator), enabled: true,
      next_due_at: 1.minute.ago)
  end

  test "default cadence is 24 hours and the dispatcher queues at most one all-campus run" do
    assert_equal 24, @schedule.interval_hours
    settings = Pastoral::Configuration.load(environment: {"ROCK_API_KEY" => "synthetic-test-key"})
    Pastoral::Configuration.stub(:load, settings) do
      assert_enqueued_with(job: PersonRefreshJob) { ScheduledPersonRefreshJob.perform_now }
      assert_equal 1, PersonRefreshRun.active.count
      assert PersonRefreshRun.active.first.all_campuses?
      assert @schedule.reload.next_due_at >= 23.hours.from_now
      assert_no_enqueued_jobs { ScheduledPersonRefreshJob.perform_now }
    end
  end

  test "disabled schedule and invalid administrator or connection never queue an import" do
    @schedule.update!(enabled: false)
    assert_no_enqueued_jobs { ScheduledPersonRefreshJob.perform_now }
    @schedule.update!(enabled: true)
    users(:administrator).update!(role: "staff")
    assert_no_enqueued_jobs { ScheduledPersonRefreshJob.perform_now }
    assert_equal "administrator_unavailable", @schedule.reload.last_error_code
    users(:administrator).update!(role: "administrator")
    Pastoral::Configuration.stub(:load, Pastoral::Configuration.load(environment: {})) do
      assert_no_enqueued_jobs { ScheduledPersonRefreshJob.perform_now }
    end
    assert_equal "directory_not_ready", @schedule.reload.last_error_code
  end

  test "failed global imports wait for review instead of losing their checkpoint to a new run" do
    run = PersonRefreshRun.start!(actor: users(:administrator))
    run.update!(status: "failed", error_code: "invalid_person_identity")
    settings = Pastoral::Configuration.load(environment: {"ROCK_API_KEY" => "synthetic-test-key"})
    Pastoral::Configuration.stub(:load, settings) do
      assert_no_enqueued_jobs { ScheduledPersonRefreshJob.perform_now }
    end
    assert_equal "failed_refresh_needs_review", @schedule.reload.last_error_code
    assert_equal 1, PersonRefreshRun.count
  end

  test "a long successful import gets a full cadence before the next import and clears old blockers" do
    run = PersonRefreshRun.start!(actor: users(:administrator))
    run.update!(status: "succeeded", finished_at: Time.current)
    @schedule.update!(last_error_code: "failed_refresh_needs_review")
    settings = Pastoral::Configuration.load(environment: {"ROCK_API_KEY" => "synthetic-test-key"})
    Pastoral::Configuration.stub(:load, settings) do
      assert_no_enqueued_jobs { ScheduledPersonRefreshJob.perform_now }
    end
    assert_nil @schedule.reload.last_error_code
    assert @schedule.due_at >= 23.hours.from_now
    assert_equal "healthy", @schedule.health
  end

  test "scheduler metadata updates do not invalidate a configuration form revision" do
    revision = @schedule.lock_version
    settings = Pastoral::Configuration.load(environment: {"ROCK_API_KEY" => "synthetic-test-key"})
    Pastoral::Configuration.stub(:load, settings) { ScheduledPersonRefreshJob.perform_now }
    assert_not_nil @schedule.reload.last_checked_at
    assert_equal revision, @schedule.lock_version
  end
end
