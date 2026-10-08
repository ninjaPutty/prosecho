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

  test "DNS interruption becomes a sanitized retryable read error" do
    Net::HTTP.stub(:start, ->(*_, **_) { raise SocketError, "private network detail" }) do
      error = assert_raises(Integrations::Rock::ReadClient::ReadError) do
        Integrations::Rock::ReadClient.new(api_key: "synthetic-test-key").campuses
      end
      assert_nil error.cause
      assert_not error.message.include?("private network detail")
    end
  end

  test "people requests use explicit numeric campus scope and allowlisted projections" do
    requests = []
    reader = client(transport: ->(request) do
      requests << request
      []
    end)
    reader.people(campus_ids: [100002, 100001], fields: %w[first_name last_name primary_campus])
    query = URI.decode_www_form(requests.last.uri.query).to_h
    assert_includes query["$filter"], "PrimaryCampusId eq 100001 or PrimaryCampusId eq 100002"
    assert_equal "Id", query["$orderby"]
    assert_includes query["$select"], "FirstName"
    assert_not query["$select"].include?("PhotoId")
    assert_nil query["loadAttributes"]
    assert_raises(ArgumentError) { reader.people(campus_ids: [], fields: ["first_name"]) }
    assert_raises(ArgumentError) do
      reader.people(campus_ids: ["1 or true"], fields: ["first_name"])
    end
    assert_raises(ArgumentError) do
      reader.people(campus_ids: [100001], fields: ["SystemNote"])
    end
    reader.people(campus_ids: [100001], fields: ["first_name"], attribute_keys: ["FirstVisit"])
    query = URI.decode_www_form(requests.last.uri.query).to_h
    assert_equal "FirstVisit", query["attributeKeys"]
    assert_equal "simple", query["loadAttributes"]
  end

  test "town-only locations and household queries cannot expand unrelated personal fields" do
    requests = []
    reader = client(transport: ->(request) do
      requests << request
      []
    end)
    reader.home_locations(301, precise: false)
    query = URI.decode_www_form(requests.last.uri.query).to_h
    assert_includes query["$filter"], "GroupLocationTypeValue/Value eq 'Home'"
    assert_includes query["$select"], "Location/City"
    assert_not query["$select"].include?("Street1")
    assert_not query["$select"].include?("Latitude")
    reader.household_members(301, campus_ids: [100001])
    query = URI.decode_www_form(requests.last.uri.query).to_h
    assert_includes query["$filter"], "Person/PrimaryCampusId eq 100001"
    assert_includes query["$filter"], "GroupMemberStatus eq 'Active'"
    assert_not query["$select"].include?("FirstName")
    assert_not query["$select"].include?("Note")
  end

  test "portrait requests are named GET reads and reject redirect or active image content" do
    [Net::HTTPFound.new("1.1", "302", "Found"), Net::HTTPOK.new("1.1", "200", "OK")].each do |response|
      response["Content-Type"] = "image/svg+xml"
      connection = Object.new
      connection.define_singleton_method(:request) do |request, &block|
        raise "Expected fixed image endpoint" unless request.uri.path == "/GetImage.ashx"
        raise "Expected GET" unless request.is_a?(Net::HTTP::Get)
        block.call(response)
      end
      Net::HTTP.stub(:start, ->(*args, **options, &block) { block.call(connection) }) do
        assert_raises(Integrations::Rock::ReadClient::ReadError) do
          Integrations::Rock::ReadClient.new(api_key: "synthetic-test-key").photo(42)
        end
      end
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

  test "keyset people queries are validated and preserve campus and population restrictions" do
    request = nil
    reader = client(transport: ->(value) do
      request = value
      []
    end)
    reader.people(campus_ids: [100001], fields: DataPolicy::MINIMUM_FIELDS, after_id: 123)
    query = URI.decode_www_form(request.uri.query).to_h
    assert_includes query["$filter"], "Id gt 123"
    assert_includes query["$filter"], "PrimaryCampusId eq 100001"
    assert_includes query["$filter"], "IsDeceased eq false"
    assert_equal "0", query["$skip"]
    assert_raises(ArgumentError) do
      reader.people(campus_ids: [100001], fields: DataPolicy::MINIMUM_FIELDS, after_id: "1 or true")
    end
  end

  test "people reads support 500 rows while campus and related reads stay bounded to 100" do
    requests = []
    reader = client(transport: ->(request) do
      requests << request
      []
    end)
    reader.people(campus_ids: [100001], fields: DataPolicy::MINIMUM_FIELDS, limit: 500)
    assert_equal "500", URI.decode_www_form(requests.last.uri.query).to_h["$top"]
    assert_raises(ArgumentError) do
      reader.people(campus_ids: [100001], fields: DataPolicy::MINIMUM_FIELDS, limit: 501)
    end
    assert_raises(ArgumentError) { reader.campuses(limit: 250) }
    assert_raises(ArgumentError) { reader.home_locations(301, limit: 250) }
    assert_raises(ArgumentError) { reader.household_members(301, limit: 250) }
  end

  test "household campus filters stay below the Rock OData expression-node limit" do
    reader = client(transport: ->(_) { flunk "must not send an oversized campus filter" })
    assert_raises(ArgumentError) do
      reader.household_members(301, campus_ids: (100001..100009).to_a)
    end
  end
end
