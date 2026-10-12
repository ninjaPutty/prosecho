require "test_helper"

class ChurchNextClientTest < ActiveSupport::TestCase
  Response = Struct.new(:code, :body, :headers) do
    def [](key)
      headers[key]
    end

    def read_body
      yield body
    end
  end

  setup do
    @origin = "https://churchnext.example.test"
    @token = "synthetic-callback-token-for-tests-only"
    @payload = {event_id: SecureRandom.uuid, church_next_user_id: "cn-101",
                prosecho_person_id: SecureRandom.uuid, linked: true}
  end

  test "callbacks use a fixed authenticated POST and require a matching acknowledgement" do
    transport = lambda do |uri, request, &block|
      assert_equal "#{@origin}/api/v1/prosecho/account_links", uri.to_s
      assert_instance_of Net::HTTP::Post, request
      assert_equal "application/json", request["Accept"]
      assert_equal "Bearer #{@token}", request["Authorization"]
      assert_equal @payload.as_json, JSON.parse(request.body)
      block.call(Response.new("200", @payload.to_json, {}))
    end
    client(transport).notify_link(@payload)
    invalid = ->(_uri, _request, &block) { block.call(Response.new("200", "{}", {})) }
    assert_raises(Integrations::ChurchNext::Client::RequestError) { client(invalid).notify_link(@payload) }
  end

  test "redirects and unexpected photo types are rejected without following them" do
    calls = 0
    redirect = lambda do |_uri, _request, &block|
      calls += 1
      block.call(Response.new("302", "", {"location" => "https://another.example.test"}))
    end
    assert_raises(Integrations::ChurchNext::Client::RequestError) { client(redirect).notify_link(@payload) }
    assert_equal 1, calls
    bad_photo = ->(_uri, _request, &block) { block.call(Response.new("200", "<svg></svg>", {"content-type" => "image/svg+xml"})) }
    assert_raises(Integrations::ChurchNext::Client::RequestError) { client(bad_photo).photo("cn-101") }
  end

  test "photos use only the configured origin and bounded private raster responses" do
    transport = lambda do |uri, request, &block|
      assert_equal "#{@origin}/api/v1/prosecho/accounts/cn-101/photo", uri.to_s
      assert_instance_of Net::HTTP::Get, request
      assert_includes request["Accept"], "image/jpeg"
      block.call(Response.new("200", "synthetic-image".b, {"content-type" => "image/jpeg"}))
    end
    assert_equal "image/jpeg", client(transport).photo("cn-101").content_type
    assert_raises(ArgumentError) { client(transport).photo("../../private") }
    oversized = lambda do |_uri, _request, &block|
      block.call(Response.new("200", "x" * (2.megabytes + 1), {"content-type" => "image/jpeg"}))
    end
    assert_raises(Integrations::ChurchNext::Client::RequestError) { client(oversized).photo("cn-101") }
  end

  test "origins with HTTP credentials paths query strings or alternate ports fail closed" do
    ["http://churchnext.example.test", "https://token@churchnext.example.test",
      "https://churchnext.example.test/path", "https://churchnext.example.test?x=1",
      "https://churchnext.example.test:444"].each do |origin|
      assert_raises(Integrations::ChurchNext::Client::ConfigurationError) do
        Integrations::ChurchNext::Client.new(base_url: origin, token: @token)
      end
    end
    assert_raises(Integrations::ChurchNext::Client::ConfigurationError) do
      Integrations::ChurchNext::Client.new(base_url: @origin, token: "bad\ncredential" * 10)
    end
  end

  private

  def client(transport)
    Integrations::ChurchNext::Client.new(base_url: @origin, token: @token, transport: transport)
  end
end
