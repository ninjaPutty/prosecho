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

  test "dispatcher queues one all-campus run at the selected GMT time" do
    @schedule.update!(scheduled_at: "09:30", next_due_at: nil)
    travel_to Time.utc(2026, 10, 10, 9, 30) do
      settings = Pastoral::Configuration.load(environment: {"ROCK_API_KEY" => "synthetic-test-key"})
      Pastoral::Configuration.stub(:load, settings) do
        assert_enqueued_with(job: PersonRefreshJob) { ScheduledPersonRefreshJob.perform_now }
        assert_equal 1, PersonRefreshRun.active.count
        assert PersonRefreshRun.active.first.all_campuses?
        assert_equal Time.utc(2026, 10, 11, 9, 30), @schedule.reload.next_due_at
        assert_no_enqueued_jobs { ScheduledPersonRefreshJob.perform_now }
      end
    end
  end

  test "the next due time is the selected GMT time after a completed refresh" do
    @schedule.update!(scheduled_at: "09:30", next_due_at: nil)
    run = PersonRefreshRun.start!(actor: users(:administrator))
    run.update!(status: "succeeded", finished_at: Time.utc(2026, 10, 10, 10))
    travel_to Time.utc(2026, 10, 10, 10, 15) do
      assert_equal Time.utc(2026, 10, 11, 9, 30), @schedule.due_at
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

  test "a completed import clears old blockers without queuing before the next GMT time" do
    run = PersonRefreshRun.start!(actor: users(:administrator))
    run.update!(status: "succeeded", finished_at: Time.current)
    @schedule.update!(scheduled_at: Time.current.strftime("%H:%M"), last_error_code: "failed_refresh_needs_review")
    settings = Pastoral::Configuration.load(environment: {"ROCK_API_KEY" => "synthetic-test-key"})
    Pastoral::Configuration.stub(:load, settings) do
      assert_no_enqueued_jobs { ScheduledPersonRefreshJob.perform_now }
    end
    assert_nil @schedule.reload.last_error_code
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
