require "test_helper"
require "fugit"

class PersistentQueueTest < ActiveSupport::TestCase
  test "ActiveJob persists readiness work and its scheduled recurrence validates" do
    original = FoundationReadinessJob.queue_adapter
    FoundationReadinessJob.queue_adapter = :solid_queue
    job = nil
    assert_difference "SolidQueue::Job.count", 1 do
      job = FoundationReadinessJob.perform_later
    end
    persisted = SolidQueue::Job.find_by!(active_job_id: job.job_id)
    assert_equal "foundation", persisted.queue_name
    assert_equal "FoundationReadinessJob", persisted.class_name
    assert SolidQueue::ReadyExecution.exists?(job_id: persisted.id)
    configuration = SolidQueue::Configuration.new
    assert configuration.valid?, configuration.errors.full_messages.join(", ")
    schedules = YAML.safe_load_file(Rails.root.join("config/recurring.yml"))
    assert_equal "FoundationReadinessJob", schedules.dig("production", "foundation_readiness", "class")
    assert Fugit.parse(schedules.dig("production", "foundation_readiness", "schedule"))
  ensure
    FoundationReadinessJob.queue_adapter = original
  end
end
