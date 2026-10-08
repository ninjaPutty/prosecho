class PersonRefreshRecoveryJob < ApplicationJob
  queue_as :foundation

  def perform
    PersonRefreshRun.active.find_each(&:dispatch!)
  end
end
