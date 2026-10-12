class ChurchNextLinkDeliveryJob < ApplicationJob
  queue_as :default

  def perform(id)
    delivery = ChurchNextLinkDelivery.find_by(id: id)
    return unless delivery

    delivery.with_lock do
      return unless delivery.status == "pending" && delivery.next_attempt_at <= Time.current

      begin
        Integrations::ChurchNext::Client.new.notify_link(delivery.payload)
        delivery.update!(status: "delivered", attempts: delivery.attempts + 1,
          delivered_at: Time.current, last_error_code: nil)
      rescue Integrations::ChurchNext::Client::ConfigurationError
        delivery.update!(next_attempt_at: 5.minutes.from_now, last_error_code: "not_configured")
      rescue Integrations::ChurchNext::Client::RequestError => error
        attempts = delivery.attempts + 1
        delay = [30 * (2**[attempts, 7].min), 3600].min
        delivery.update!(attempts: attempts, next_attempt_at: delay.seconds.from_now,
          last_error_code: error.message)
      end
    end
  end
end
