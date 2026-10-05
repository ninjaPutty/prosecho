require "test_helper"

class PastoralConfigurationTest < ActiveSupport::TestCase
  test "default configuration blocks all live integrations" do
    settings = Pastoral::Configuration.load(environment: {})
    assert_not settings.ready?
    assert_not settings.live_sync_enabled?
    assert_includes settings.blockers, "Data decisions have not been approved"
    assert_nil settings.rock_api_key
    assert settings.read_only?
    assert_not settings.blockers.any? { |blocker| blocker.include?("permission") }
  end

  test "a runtime sync flag and key cannot bypass pending data decisions" do
    settings = Pastoral::Configuration.load(environment: {
      "ROCK_API_KEY" => "synthetic-test-key", "ROCK_SYNC_ENABLED" => "true"
    })
    assert_not settings.live_sync_enabled?
    assert_not settings.inspect.include?("synthetic-test-key")
  end

  test "map configuration rejects public OSM services and unexpected Rock hosts" do
    settings = Pastoral::Configuration.load(environment: {
      "PASTORAL_GEOCODER_URL" => "https://nominatim.openstreetmap.org",
      "PASTORAL_TILE_URL" => "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
      "ROCK_BASE_URL" => "https://elsewhere.example.test"
    })
    assert_includes settings.blockers, "Rock host must be https://rock.chapel.org"
    assert_includes settings.blockers, "Map providers must not use public OSM services"
  end
end
