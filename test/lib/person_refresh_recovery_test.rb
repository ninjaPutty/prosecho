require "test_helper"
require_relative "../support/directory_policy"

class PersonRefreshRecoveryTest < ActiveSupport::TestCase
  include DirectoryPolicy

  setup do
    confirm_directory_policy
    @run = PersonRefreshRun.start!(actor: users(:administrator))
    @adapter = PersonRefreshJob.queue_adapter
    PersonRefreshJob.queue_adapter = :solid_queue
  end

  teardown do
    PersonRefreshJob.queue_adapter = @adapter
  end

  test "recovery dispatches orphaned running work and does not duplicate ready work" do
    @run.update!(status: "running", page_count: 3, next_offset: 150)
    assert_difference "SolidQueue::Job.count", 1 do
      PersonRefreshRecoveryJob.perform_now
    end
    job_id = @run.reload.job_id
    assert_not_nil job_id
    assert_no_difference "SolidQueue::Job.count" do
      PersonRefreshRecoveryJob.perform_now
      @run.dispatch!
    end
    assert_equal 150, @run.reload.next_offset
    assert_equal job_id, @run.job_id
  end

  test "a live claim is retained but a stale worker claim can be recovered" do
    @run.dispatch!
    job = SolidQueue::Job.find_by!(active_job_id: @run.reload.job_id)
    job.ready_execution.destroy!
    process = SolidQueue::Process.create!(kind: "Worker", pid: 12345,
      name: "recovery-fixture", hostname: "fixture", last_heartbeat_at: Time.current,
      metadata: {"queues" => "directory"})
    SolidQueue::ClaimedExecution.create!(job: job, process: process)
    assert_no_difference "SolidQueue::Job.count" do
      assert_not @run.dispatch!
    end
    process.update!(last_heartbeat_at: 10.minutes.ago)
    assert_difference "SolidQueue::Job.count", 1 do
      assert @run.dispatch!
    end
  end

  test "retry scheduling preserves progress and terminal runs are not restarted" do
    @run.update!(status: "queued", page_count: 2, next_offset: 100,
      error_code: "rock_read_failed", retry_at: 1.minute.from_now)
    @run.dispatch!
    job = SolidQueue::Job.find_by!(active_job_id: @run.reload.job_id)
    assert job.scheduled_execution
    assert_equal 100, @run.next_offset
    @run.update!(status: "succeeded")
    assert_no_difference "SolidQueue::Job.count" do
      assert_not @run.dispatch!
    end
  end

  test "failed retained checkpoints require explicit resume and preserve their diagnostic history" do
    @run.update!(status: "failed", error_code: "invalid_person_identity", page_count: 5,
      next_offset: 250, last_rock_id: 900, error_details: {"phase" => "read", "rock_id" => 999})
    assert_no_difference "SolidQueue::Job.count" do
      PersonRefreshRecoveryJob.perform_now
    end
    @run.resume!
    assert @run.dispatch!
    assert_equal "queued", @run.reload.status
    assert_equal 900, @run.last_rock_id
    assert_equal 250, @run.next_offset
    assert_equal 999, @run.error_details["rock_id"]
  end

  test "lost checkpoints and changed policy cannot resume a failed run" do
    @run.update!(status: "failed", error_code: "invalid_source_records", checkpoint_retained: false)
    assert_not @run.resumable?
    assert_raises(PersonRefreshRun::NotReady) { @run.resume! }
    @run.update!(checkpoint_retained: true)
    DataPolicy.current.update!(history_retention_days: 180)
    assert_not @run.resumable?
    assert_raises(PersonRefreshRun::NotReady) { @run.resume! }
    assert_equal "failed", @run.reload.status
  end

  test "failed resume cannot overlap another user's active refresh" do
    @run.update!(status: "failed", error_code: "invalid_person_identity")
    PersonRefreshRun.start!(actor: users(:administrator))
    assert_raises(PersonRefreshRun::AlreadyRunning) { @run.resume! }
    assert_equal "failed", @run.reload.status
  end

  test "the scheduling entry point enqueues all-campus work and rejects staff" do
    @run.update!(status: "succeeded")
    run = nil
    assert_difference "SolidQueue::Job.count", 1 do
      run = PersonRefreshRun.enqueue!(actor: users(:administrator))
    end
    assert run.all_campuses?
    assert_equal Campus.order(:id).pluck(:id), run.campus_ids
    assert_no_difference "SolidQueue::Job.count" do
      assert_equal run.id, PersonRefreshRun.enqueue!(actor: users(:administrator)).id
      assert_raises(PersonRefreshRun::NotReady) do
        PersonRefreshRun.enqueue!(actor: users(:staff))
      end
    end
  end

  test "campus grants do not affect global retry but legacy scoped runs cannot be widened on resume" do
    @run.update!(status: "failed", error_code: "invalid_person_identity")
    users(:administrator).campuses << campuses(:north)
    users(:administrator).campus_accesses.destroy_all
    assert @run.resumable?
    @run.update!(all_campuses: false)
    assert_not @run.resumable?
    assert_raises(PersonRefreshRun::NotReady) { @run.resume! }
  end
end
