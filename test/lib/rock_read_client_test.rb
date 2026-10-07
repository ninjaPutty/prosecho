require "test_helper"
require "minitest/mock"
require "net/http"

class RockReadClientTest < ActiveSupport::TestCase
  def client(transport: ->(_) { {"Id" => 123} })
    Integrations::Rock::ReadClient.new(api_key: "synthetic-test-key", transport: transport)
  end

  test "named reads create only GET requests with the documented authentication" do
    requests = []
    reader = client(transport: ->(request) do
      requests << request
      {"Id" => 123}
    end)
    reader.person(123)
    reader.campuses
    reader.household_members(456)
    reader.home_locations(456)
    assert requests.all? { |request| request.is_a?(Net::HTTP::Get) }
    assert requests.all? { |request| request["Authorization-Token"] == "synthetic-test-key" }
    assert_equal "/api/People/123", requests.first.uri.path
    campus_query = URI.decode_www_form(requests[1].uri.query).to_h
    assert_equal "Id,Name,IsActive", campus_query["$select"]
    assert_equal "Id", campus_query["$orderby"]
    assert_not reader.inspect.include?("synthetic-test-key")
  end

  test "GET endpoints that can mutate and arbitrary paths are not exposed" do
    reader = client(transport: ->(_) { flunk "must not reach transport" })
    assert_not reader.respond_to?(:request)
    assert_not reader.respond_to?(:get)
    assert_not reader.respond_to?(:post)
    assert_raises(ArgumentError) { reader.person("../People/SetContext/123") }
    assert_raises(ArgumentError) { reader.home_locations("1 or true") }
    assert_raises(ArgumentError) { reader.campuses(limit: 10000) }
    assert_raises(ArgumentError) do
      Integrations::Rock::ReadClient.new(api_key: "synthetic-test-key", read_only: false)
    end
    assert reader.read_only?
  end

  test "credentials cannot be sent to a different host or a redirect" do
    assert_raises(Integrations::Rock::ReadClient::ConfigurationError) do
      Integrations::Rock::ReadClient.new(api_key: "synthetic-test-key",
        base_url: "https://evil.example.test")
    end
    redirect = Net::HTTPFound.new("1.1", "302", "Found")
    redirect["Location"] = "https://evil.example.test"
    connection = Object.new
    connection.define_singleton_method(:request) { |_| redirect }
    requests = 0
    start = ->(*args, **options, &block) do
      requests += 1
      block.call(connection)
    end
    Net::HTTP.stub(:start, start) do
      assert_raises(Integrations::Rock::ReadClient::ReadError) do
        Integrations::Rock::ReadClient.new(api_key: "synthetic-test-key").person(123)
      end
    end
    assert_equal 1, requests
  end

  test "invalid upstream JSON is not retained in error messages or causes" do
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.define_singleton_method(:body) { "synthetic-private-payload: not JSON" }
    connection = Object.new
    connection.define_singleton_method(:request) { |_| response }
    Net::HTTP.stub(:start, ->(*args, **options, &block) { block.call(connection) }) do
      error = assert_raises(Integrations::Rock::ReadClient::ReadError) do
        Integrations::Rock::ReadClient.new(api_key: "synthetic-test-key").person(123)
      end
      assert_nil error.cause
      assert_not error.message.include?("synthetic-private-payload")
    end
  end

  test "precise home reads retain addresses without unsupported Rock coordinate projections" do
    requests = []
    reader = client(transport: ->(request) do
      requests << request
      []
    end)
    reader.home_locations(301, precise: true)
    columns = URI.decode_www_form(requests.first.uri.query).to_h.fetch("$select").split(",")
    %w[Location/Street1 Location/Street2 Location/PostalCode Location/City].each do |column|
      assert_includes columns, column
    end
    assert_not_includes columns, "Location/Latitude"
    assert_not_includes columns, "Location/Longitude"
  end
end
