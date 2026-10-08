require "test_helper"
require "json"

class PersonMapperTest < ActiveSupport::TestCase
  def mapper(fields: DataPolicy::FIELD_LABELS.keys, attribute_keys: ["FirstVisit"])
    Integrations::Rock::PersonMapper.new(fields: fields, attribute_keys: attribute_keys,
      campuses: {100001 => {id: campuses(:north).id, name: "Example North"}},
      today: Date.new(2026, 10, 5))
  end

  def person
    JSON.parse(file_fixture("rock_person.json").read)
  end

  def home(id: 501, kind: "Home")
    {
      "LocationId" => id, "GroupLocationTypeValue" => {"Value" => kind},
      "Location" => {"Id" => id, "IsActive" => true, "Street1" => "10 Fixture Lane",
                     "City" => "Example Town", "State" => "ZZ", "Country" => "US",
                     "PostalCode" => "00000", "Latitude" => 42.0, "Longitude" => -88.0}
    }
  end

  test "normalizes preferred name age lookups and only approved attributes" do
    result = mapper.map(person, locations: [home])
    assert_equal "Tay Example", result.display_name
    assert_equal 36, result.age
    assert_equal Date.new(1990, 5, 10), result.birth_date
    assert_equal "Example connection", result.connection_status[:label]
    assert_equal "Example North", result.campus[:name]
    assert_equal "known", result.home_address[:status]
    assert_equal({"FirstVisit" => "2021-01-01"}, result.attributes)
    serialized = result.to_h.to_s
    assert_not serialized.include?("excluded")
    assert_not result.inspect.include?("Taylor")
    assert result.home_address.frozen?
  end

  test "missing or ambiguous homes never use previous mailing or mapped locations" do
    previous = home(kind: "Previous").merge("IsMappedLocation" => true, "IsMailingLocation" => true)
    missing = mapper.map(person, locations: [previous])
    assert_equal "missing", missing.home_address[:status]
    assert_nil missing.home_address[:city]
    ambiguous = mapper.map(person, locations: [home, home(id: 502)])
    assert_equal "ambiguous", ambiguous.home_address[:status]
    assert_nil ambiguous.home_address[:street1]
    assert_nil ambiguous.home_address[:latitude]
    duplicate = mapper.map(person, locations: [home, home])
    assert_equal "known", duplicate.home_address[:status]
  end

  test "partial birth dates unknown lookups and denied fields remain unknown or absent" do
    row = person.merge("BirthYear" => nil, "ConnectionStatusValue" => nil)
    result = mapper.map(row)
    assert_nil result.age
    assert_nil result.birth_date
    assert_nil result.connection_status[:label]
    assert_includes result.issues, "birth_date_partial"
    limited = mapper(fields: DataPolicy::MINIMUM_FIELDS, attribute_keys: []).map(person)
    assert_equal "Taylor Example", limited.display_name
    assert_nil limited.birth_date
    assert_nil limited.photo_id
    assert_nil limited.home_address
    assert_nil limited.household
    assert_empty limited.attributes
  end

  test "household output contains only active authorized facts and stable member GUIDs" do
    member = {
      "PersonId" => 102, "GroupRoleId" => 11, "GroupMemberStatus" => 1,
      "IsArchived" => false, "GroupRole" => {"Id" => 11, "Name" => "Child"},
      "Person" => {"Id" => 102, "Guid" => "00000000-0000-4000-8000-000000000102",
                   "PrimaryCampusId" => 100001}
    }
    result = mapper.map(person, members: [member,
      member.merge("IsArchived" => true),
      member.merge("Person" => member["Person"].merge("PrimaryCampusId" => 100002))])
    assert_equal 1, result.household[:members].size
    assert_equal member["Person"]["Guid"], result.household[:members].first[:person_guid]
    assert_equal "Child", result.household[:members].first[:role][:label]
    assert_equal "authorized_campuses", result.household[:scope]
    assert_not result.household[:complete]
    assert_not result.to_h.to_s.include?("birth_event")
  end

  test "invalid identities fail safely while invalid dates coordinates and lookups stay unknown" do
    assert_raises(Integrations::Rock::PersonMapper::MappingError) do
      mapper.map(person.merge("Guid" => "not-a-guid"))
    end
    row = person.merge("BirthMonth" => 2, "BirthDay" => 31,
      "ConnectionStatusValue" => {"Id" => 999, "Value" => "wrong lookup"})
    location = home
    location["Location"]["Latitude"] = 999
    result = mapper.map(row, locations: [location])
    assert_nil result.birth_date
    assert_nil result.age
    assert_nil result.connection_status[:label]
    assert_nil result.home_address[:latitude]
    town_only = Integrations::Rock::PersonMapper.new(fields: DataPolicy::FIELD_LABELS.keys,
      campuses: {100001 => {id: campuses(:north).id, name: "Example North"}}, precise: false)
    result = town_only.map(person, locations: [home])
    assert_equal "Example Town", result.home_address[:city]
    assert_nil result.home_address[:street1]
    assert_nil result.home_address[:latitude]
  end
end
