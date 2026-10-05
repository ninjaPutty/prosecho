require "test_helper"

class FoundationReadinessJobTest < ActiveJob::TestCase
  test "readiness job records blockers without enqueuing a live sync" do
    assert_no_enqueued_jobs do
      assert_difference "FoundationCheck.count", 1 do
        FoundationReadinessJob.perform_now
      end
    end
    check = FoundationCheck.order(:created_at).last
    assert_not check.ready
    assert_includes check.blockers, "Data decisions have not been approved"
  end
end
