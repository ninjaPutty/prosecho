class PersonRefreshJob < ApplicationJob
  queue_as :directory
  # Queue tables and refresh state share PostgreSQL, so dispatch is atomic.
  self.enqueue_after_transaction_commit = false

  def perform(run_id)
    run = PersonRefreshRun.find_by(id: run_id)
    Directory::Refresh.new(run: run).call if run
  end
end
