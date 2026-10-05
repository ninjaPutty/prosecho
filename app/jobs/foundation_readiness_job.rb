class FoundationReadinessJob < ApplicationJob
  queue_as :foundation

  def perform
    settings = Pastoral::Configuration.load
    FoundationCheck.create!(blockers: settings.blockers, ready: settings.ready?)
    # Phase 0 never fetches Rock records or enqueues a live synchronization.
    FoundationCheck.where(created_at: ...30.days.ago).delete_all
  end
end
