class ChurchNextLinkDelivery < ApplicationRecord
  belongs_to :church_next_account
  after_create_commit :queue_delivery

  validates :prosecho_person_id, presence: true
  validates :status, inclusion: {in: %w[delivered pending]}

  def payload
    {event_id: id, church_next_user_id: church_next_account.external_user_id,
     prosecho_person_id: prosecho_person_id, linked: true}
  end

  private

  def queue_delivery
    ChurchNextLinkDeliveryJob.perform_later(id)
  rescue ActiveJob::EnqueueError, ActiveRecord::ActiveRecordError
    Rails.logger.warn("ChurchNext delivery enqueue failed; the durable outbox will recover it")
  end
end
