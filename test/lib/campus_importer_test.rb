require "test_helper"

class CampusImporterTest < ActiveSupport::TestCase
  def fake_client(&block)
    Object.new.tap { |client| client.define_singleton_method(:campuses, &block) }
  end

  def importer(client)
    Integrations::Rock::CampusImporter.new(actor: users(:administrator), client: client)
  end

  test "refresh upserts Rock names and status while preserving local identity grants and parents" do
    north = campuses(:north)
    north.update!(parent: campuses(:south))
    data = [{"Id" => north.rock_id, "Name" => "North from Rock", "IsActive" => false},
      {"Id" => 100003, "Name" => "New from Rock", "IsActive" => true}]
    client = fake_client { |**_| data }
    result = importer(client).call
    assert_equal 1, result.created
    assert_equal 1, result.updated
    assert_equal "North from Rock", north.reload.name
    assert_not north.active?
    assert_equal campuses(:south).id, north.parent_id
    assert CampusAccess.exists?(user: users(:staff), campus_id: north.id)
    assert campuses(:south).reload.active?, "A missing source row must not infer removal"
    added = Campus.find_by!(rock_id: 100003)
    assert_nil added.parent_id
    assert_empty added.campus_accesses
    assert_no_difference ["Campus.count", "AccessEvent.count"] do
      result = importer(client).call
      assert_equal 0, result.created
      assert_equal 0, result.updated
      assert_equal 2, result.unchanged
    end
  end

  test "all pages are fetched in stable order before a catalog is applied" do
    requests = []
    first = (1..100).map { |id| {"Id" => id, "Name" => "Example #{id}", "IsActive" => true} }
    client = fake_client do |limit:, offset:|
      requests << [limit, offset]
      offset.zero? ? first : [{"Id" => 101, "Name" => "Last example", "IsActive" => true}]
    end
    result = importer(client).call
    assert_equal [[100, 0], [100, 100]], requests
    assert_equal 101, result.created
    assert Campus.exists?(rock_id: 101)
  end

  test "a later-page failure or malformed catalog applies no partial changes" do
    first = (1..100).map { |id| {"Id" => id, "Name" => "Example #{id}", "IsActive" => true} }
    client = fake_client do |**options|
      raise Integrations::Rock::ReadClient::ReadError, "unavailable" if options[:offset].positive?
      first
    end
    assert_no_difference ["Campus.count", "AccessEvent.count"] do
      assert_raises(Integrations::Rock::ReadClient::ReadError) { importer(client).call }
    end
    north_id = campuses(:north).rock_id
    malformed = fake_client do |**_|
      [{"Id" => north_id, "Name" => "Do not apply", "IsActive" => false},
        {"Id" => 100003, "Name" => "Invalid status", "IsActive" => nil}]
    end
    assert_raises(Integrations::Rock::CampusImporter::ImportError) { importer(malformed).call }
    assert_equal "Example North", campuses(:north).reload.name
    assert campuses(:north).active?
  end

  test "duplicate IDs and invalid IDs are rejected without writing" do
    row = {"Id" => 100003, "Name" => "Example", "IsActive" => true}
    [[row, row], [row.merge("Id" => -1)], [row.merge("Id" => "1 or true")]].each do |rows|
      assert_no_difference "Campus.count" do
        client = fake_client { |**_| rows }
        assert_raises(Integrations::Rock::CampusImporter::ImportError) { importer(client).call }
      end
    end
  end

  test "non-administrators cannot fetch or import a catalog" do
    client = fake_client { |**_| flunk "Unauthorized access must not contact Rock" }
    service = Integrations::Rock::CampusImporter.new(actor: users(:staff), client: client)
    assert_raises(Access::Provisioner::NotAuthorized) { service.call }
  end
end
