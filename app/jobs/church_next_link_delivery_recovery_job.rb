class ChurchNextLinkDeliveryRecoveryJob < ApplicationJob
  queue_as :default

  def perform
    ChurchNextLinkDelivery.where(status: "pending", next_attempt_at: ..Time.current)
      .order(:next_attempt_at).limit(100).pluck(:id).each do |id|
      ChurchNextLinkDeliveryJob.perform_later(id)
    end
  end
end
