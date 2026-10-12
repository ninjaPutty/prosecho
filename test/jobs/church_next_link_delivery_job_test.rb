require "test_helper"
require "minitest/mock"

class ChurchNextLinkDeliveryJobTest < ActiveJob::TestCase
  setup do
    @account = ChurchNextAccount.create!(external_user_id: "synthetic-101", first_name: "Alex",
      last_name: "Example", email: "alex@example.test", email_verified: true, status: "linked",
      person_profile: person_profiles(:alex), linked_at: Time.current)
    @delivery = @account.create_link_delivery!(prosecho_person_id: person_profiles(:alex).id)
  end

  test "delivery is durable idempotent and contains identifiers only" do
    sent = []
    client = Object.new
    client.define_singleton_method(:notify_link) { |payload| sent << payload }
    Integrations::ChurchNext::Client.stub(:new, client) do
      ChurchNextLinkDeliveryJob.perform_now(@delivery.id)
      ChurchNextLinkDeliveryJob.perform_now(@delivery.id)
    end
    assert_equal "delivered", @delivery.reload.status
    assert_equal 1, sent.length
    assert_equal @delivery.id, sent.first[:event_id]
    assert_equal true, sent.first[:linked]
    assert_equal [:church_next_user_id, :event_id, :linked, :prosecho_person_id], sent.first.keys.sort
  end

  test "failed callbacks retry without undoing the link or exposing errors" do
    unavailable = -> { raise Integrations::ChurchNext::Client::RequestError, "network_unavailable" }
    Integrations::ChurchNext::Client.stub(:new, unavailable) do
      ChurchNextLinkDeliveryJob.perform_now(@delivery.id)
    end
    assert_equal "pending", @delivery.reload.status
    assert_equal "network_unavailable", @delivery.last_error_code
    assert_operator @delivery.next_attempt_at, :>, Time.current
    assert_equal "linked", @account.reload.status
    assert_equal 1, @delivery.attempts
  end

  test "unconfigured callbacks remain pending and recovery finds due deliveries" do
    unavailable = -> { raise Integrations::ChurchNext::Client::ConfigurationError }
    Integrations::ChurchNext::Client.stub(:new, unavailable) do
      ChurchNextLinkDeliveryJob.perform_now(@delivery.id)
    end
    assert_equal "not_configured", @delivery.reload.last_error_code
    @delivery.update!(next_attempt_at: 1.second.ago)
    assert_enqueued_with(job: ChurchNextLinkDeliveryJob, args: [@delivery.id]) do
      ChurchNextLinkDeliveryRecoveryJob.perform_now
    end
  end
end
