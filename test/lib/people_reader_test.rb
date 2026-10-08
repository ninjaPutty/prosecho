require "test_helper"
require "json"

class PeopleReaderTest < ActiveSupport::TestCase
  setup do
    @actor = users(:staff)
    @row = JSON.parse(file_fixture("rock_person.json").read)
    Access::Provisioner.new(actor: users(:administrator)).save_data_policy(revision: "new",
      attributes: {status: "confirmed", profile_retention_days: 90,
                   history_retention_days: 365, log_retention_days: 90, backup_retention_days: 30,
                   address_handling: "Omit missing or ambiguous homes.",
                   household_handling: "Report membership facts without guessing life events."})
  end

  def fake_client(row: @row, &callback)
    client = Object.new
    client.define_singleton_method(:people) do |**options|
      callback&.call(:people, options)
      [row]
    end
    client.define_singleton_method(:home_locations) do |family_id, **options|
      callback&.call(:home_locations, options.merge(family_id: family_id))
      []
    end
    client.define_singleton_method(:household_members) do |family_id, **options|
      callback&.call(:household_members, options.merge(family_id: family_id))
      []
    end
    client
  end

  test "reads a bounded campus-scoped page and respects precise-location and photo permissions" do
    calls = []
    client = fake_client { |operation, options| calls << [operation, options] }
    page = Integrations::Rock::PeopleReader.new(actor: @actor, client: client).read_page(limit: 1)
    assert_equal 1, page.people.size
    assert_equal 1, page.next_offset
    assert_equal [100001], calls.first.last[:campus_ids]
    assert_includes calls.first.last[:fields], "photo"
    assert_equal false, calls.find { |call| call.first == :home_locations }.last[:precise]
    assert_equal [100001], calls.find { |call| call.first == :household_members }.last[:campus_ids]
    assert_equal 42, page.people.first.photo_id
    assert AccessEvent.exists?(actor: @actor, resource: "directory", outcome: "allowed")
    @actor.update!(view_photos: false)
    calls.clear
    page = Integrations::Rock::PeopleReader.new(actor: @actor, client: client).read_page
    assert_not calls.first.last[:fields].include?("photo")
    assert_nil page.people.first.photo_id
  end

  test "a draft policy or absent campus scope cannot contact Rock" do
    client = fake_client { |*_| flunk "Must not contact Rock" }
    assert_raises(Integrations::Rock::PeopleReader::NotAuthorized) do
      Integrations::Rock::PeopleReader.new(actor: users(:administrator), client: client).read_page
    end
    DataPolicy.current.update!(status: "draft", confirmed_at: nil, confirmed_by: nil)
    assert_raises(Integrations::Rock::PeopleReader::PolicyNotReady) do
      Integrations::Rock::PeopleReader.new(actor: @actor, client: client).read_page
    end
  end

  test "unexpected out-of-scope people are rejected before related data is fetched" do
    row = @row.merge("PrimaryCampusId" => 100002)
    client = fake_client(row: row) do |operation, _|
      flunk "No related read is allowed" unless operation == :people
    end
    assert_raises(Integrations::Rock::PeopleReader::NotAuthorized) do
      Integrations::Rock::PeopleReader.new(actor: @actor, client: client).read_page
    end
  end

  test "policy changes or access revocations during reads discard the result" do
    client = fake_client do |operation, _|
      DataPolicy.current.update!(status: "draft") if operation == :people
    end
    assert_raises(Integrations::Rock::PeopleReader::PolicyNotReady) do
      Integrations::Rock::PeopleReader.new(actor: @actor, client: client).read_page
    end
  end

  test "campus revocation after the person request prevents related requests" do
    actor = @actor
    client = fake_client do |operation, _|
      flunk "Must not read related data after revocation" unless operation == :people
      actor.campus_accesses.destroy_all
    end
    assert_raises(Integrations::Rock::PeopleReader::NotAuthorized) do
      Integrations::Rock::PeopleReader.new(actor: actor, client: client).read_page
    end
  end

  test "denied policy fields cause no related reads or data to appear" do
    policy = DataPolicy.current
    policy.update!(selected_fields: DataPolicy::MINIMUM_FIELDS)
    calls = []
    client = fake_client { |operation, options| calls << [operation, options] }
    page = Integrations::Rock::PeopleReader.new(actor: @actor, client: client).read_page
    assert_equal [:people], calls.map(&:first)
    assert_equal DataPolicy::MINIMUM_FIELDS, calls.first.last[:fields]
    assert_nil page.people.first.home_address
    assert_nil page.people.first.household
    assert_nil page.people.first.photo_id
  end

  test "duplicate source identities are normalized without truncating pagination" do
    client = fake_client
    rows = [@row, @row.merge("NickName" => "Updated")]
    client.define_singleton_method(:people) { |**_| rows }
    page = Integrations::Rock::PeopleReader.new(actor: @actor, client: client).read_page(limit: 2)
    assert_equal 2, page.people.size
    assert_equal 2, page.next_offset
    assert_equal @row["Id"], page.last_rock_id
    assert_equal "Updated Example", page.people.last.display_name
  end

  test "keyset reads use the saved source ID rather than a shifting skip offset" do
    options = nil
    client = fake_client { |operation, args| options = args if operation == :people }
    Integrations::Rock::PeopleReader.new(actor: @actor, client: client)
      .read_page(limit: 1, offset: 36300, after_id: 100)
    assert_equal 100, options[:after_id]
    assert_equal 0, options[:offset]
  end

  test "large pages preserve source-row pagination and reject more than 500 rows" do
    client = fake_client
    row = @row
    client.define_singleton_method(:people) { |**_| Array.new(500, row) }
    page = Integrations::Rock::PeopleReader.new(actor: @actor, client: client).read_page(limit: 500)
    assert_equal 500, page.people.size
    assert_equal 500, page.next_offset
    assert_raises(ArgumentError) do
      Integrations::Rock::PeopleReader.new(actor: @actor, client: client).read_page(limit: 501)
    end
  end

  test "an administrator import reads all campuses and policy-approved sensitive fields without viewer grants" do
    actor = users(:administrator)
    inactive = Campus.create!(name: "Inactive Example", rock_id: 100003, active: false)
    run = PersonRefreshRun.start!(actor: actor)
    assert actor.campuses.empty?
    assert_not actor.view_photos?
    assert_not actor.view_locations?
    calls = []
    row = @row.merge("PrimaryCampusId" => campuses(:south).rock_id)
    client = fake_client(row: row) { |operation, options| calls << [operation, options] }
    page = Integrations::Rock::PeopleReader.new(actor: actor, client: client, import_run: run).read_page
    assert_equal Campus.order(:rock_id).pluck(:rock_id), calls.first.last[:campus_ids].sort
    assert_includes calls.first.last[:campus_ids], inactive.rock_id
    assert_includes calls.first.last[:fields], "photo"
    assert calls.find { |call| call.first == :home_locations }.last[:precise]
    assert_equal campuses(:south).id, page.people.first.campus[:id]
    assert_empty PersonProfile.visible_to(actor)
  end

  test "import mode cannot be used by staff or by another actor and rechecks administrator status" do
    actor = users(:administrator)
    run = PersonRefreshRun.start!(actor: actor)
    client = fake_client { |*_| flunk "unauthorized import must not read Rock" }
    assert_raises(Integrations::Rock::PeopleReader::NotAuthorized) do
      Integrations::Rock::PeopleReader.new(actor: @actor, client: client, import_run: run).read_page
    end
    client = fake_client do |operation, _|
      actor.update!(role: "staff") if operation == :people
      flunk "demotion must prevent related reads" unless operation == :people
    end
    assert_raises(Integrations::Rock::PeopleReader::NotAuthorized) do
      Integrations::Rock::PeopleReader.new(actor: actor, client: client, import_run: run).read_page
    end
  end

  test "large import scopes partition and fully paginate household reads without truncation" do
    10.times do |index|
      Campus.create!(name: "Catalog Example #{index}", rock_id: 100003 + index)
    end
    actor = users(:administrator)
    run = PersonRefreshRun.start!(actor: actor)
    calls = []
    client = fake_client
    client.define_singleton_method(:household_members) do |_, **options|
      calls << options
      options[:offset].zero? ? Array.new(100, {}) : []
    end
    page = Integrations::Rock::PeopleReader.new(actor: actor, client: client, import_run: run).read_page
    assert_equal 1, page.people.size
    assert_equal [0, 100, 0, 100], calls.map { |call| call[:offset] }
    assert_equal [8, 8, 4, 4], calls.map { |call| call[:campus_ids].size }
    assert_equal Campus.pluck(:rock_id).sort, calls.flat_map { |call| call[:campus_ids] }.uniq.sort
  end
end
