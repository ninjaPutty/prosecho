require "test_helper"

class RockFamilyCacheTest < ActiveSupport::TestCase
  test "LRU eviction preserves empty results and limits both families and row count" do
    cache = Integrations::Rock::FamilyCache.new(max_entries: 2, max_rows: 3)
    cache.store(1, [])
    cache.store(2, [{"Id" => 1}])
    assert_equal [], cache.fetch(1)
    cache.store(3, [{"Id" => 2}])
    assert_nil cache.fetch(2)
    assert_equal [], cache.fetch(1)
    cache.store(4, Array.new(4) { {"Id" => 3} })
    assert_nil cache.fetch(4)
    assert_equal [], cache.fetch(1)
    cache.clear
    assert_nil cache.fetch(1)
  end

  test "cached values are immutable private copies and inspection omits source fields" do
    cache = Integrations::Rock::FamilyCache.new
    source = [{"Location" => {"Street1" => "synthetic-private-address"}}]
    cache.store(1, source)
    source.first["Location"]["Street1"] = "changed"
    value = cache.fetch(1)
    assert_equal "synthetic-private-address", value.first["Location"]["Street1"]
    assert value.first["Location"].frozen?
    assert_not_includes cache.inspect, "synthetic-private-address"
  end
end
