require "test_helper"
require "json"
require "minitest/mock"
require_relative "../support/directory_policy"

class PersonProjectionRefreshTest < ActiveSupport::TestCase
  include DirectoryPolicy

  setup do
    @policy = confirm_directory_policy
    @actor = users(:staff)
    @run = PersonRefreshRun.start!(actor: @actor)
    row = JSON.parse(file_fixture("rock_person.json").read)
    @person = Integrations::Rock::PersonMapper.new(fields: DataPolicy::FIELD_LABELS.keys,
      campuses: {100001 => {id: campuses(:north).id, name: "Example North"}}).map(row)
  end

  def reader(&block)
    Object.new.tap do |object|
      object.define_singleton_method(:read_page) { |**arguments| block.call(**arguments) }
    end
  end

  def page(people: [@person], offset: 0, next_offset: nil)
    Integrations::Rock::PeopleReader::Page.new(people: people, offset: offset,
      limit: 50, next_offset: next_offset, policy_revision: @policy.revision, observed_at: Time.current)
  end

  test "publishes a completed refresh by stable GUID and clears staged entries" do
    batch = page
    fake = reader { |**_| batch }
    id = person_profiles(:alex).id
    Directory::Refresh.new(run: @run, reader: fake).call
    profile = PersonProfile.find_by!(rock_guid: @person.rock_guid)
    assert_equal id, profile.id
    assert_equal @person.display_name, profile.display_name
    assert_equal @policy.revision, profile.policy_revision
    assert_equal "succeeded", @run.reload.status
    assert_empty @run.entries
    assert_equal 1, @run.imported_count
  end

  test "refresh pages default to 250 and can be increased to 500" do
    fake = reader do |limit:, **_|
      assert_equal 250, limit
      page
    end
    Directory::Refresh.new(run: @run, reader: fake).call
    assert_equal "succeeded", @run.reload.status
    larger = PersonRefreshRun.start!(actor: @actor)
    fake = reader do |limit:, **_|
      assert_equal 500, limit
      page
    end
    Directory::Refresh.new(run: larger, reader: fake, page_size: "500").call
    assert_equal "succeeded", larger.reload.status
  end

  test "invalid page size pauses with a specific diagnostic before reading Rock" do
    fake = reader { |**_| flunk "must not contact Rock with an invalid page size" }
    Directory::Refresh.new(run: @run, reader: fake, page_size: "501").call
    assert_equal "failed", @run.reload.status
    assert_equal "invalid_page_size", @run.error_code
    assert_equal "read", @run.error_details["phase"]
    assert @run.checkpoint_retained?
  end

  test "a network failure preserves committed pages and retries from the saved offset" do
    first = page(next_offset: 50)
    fake = reader do |offset:, **_|
      raise Integrations::Rock::ReadClient::ReadError, "unavailable" if offset.positive?
      first
    end
    Directory::Refresh.new(run: @run, reader: fake).call
    assert_equal "Alex Example", person_profiles(:alex).reload.display_name
    assert_equal "queued", @run.reload.status
    assert_equal 1, @run.entries.count
    assert_equal 50, @run.next_offset
    assert_equal 1, @run.page_count
    assert_equal "rock_read_failed", @run.error_code
    travel 2.minutes do
      last = page(people: [], offset: 50)
      resumed = reader do |offset:, **_|
        assert_equal 50, offset
        last
      end
      Directory::Refresh.new(run: @run, reader: resumed).call
    end
    assert_equal "succeeded", @run.reload.status
    assert_equal 1, @run.imported_count
    assert_empty @run.entries
  end

  test "duplicates within and across pages update one staged identity and advance the keyset cursor" do
    updated = Integrations::Rock::PersonRecord.new(**@person.to_h.merge(
      rock_id: @person.rock_id + 1, display_name: "Updated Example"
    ))
    fake = reader do |offset:, after_id:, **_|
      if offset.zero?
        assert_equal 0, after_id
        page(people: [@person, @person], next_offset: 50)
      else
        assert_equal @person.rock_id, after_id
        page(people: [updated], offset: 50)
      end
    end
    Directory::Refresh.new(run: @run, reader: fake).call
    assert_equal "succeeded", @run.reload.status
    assert_equal 2, @run.duplicate_count
    assert_equal 1, @run.imported_count
    assert_equal updated.rock_id, @run.last_rock_id
    assert_equal "Updated Example", PersonProfile.find_by!(rock_guid: @person.rock_guid).display_name
  end

  test "mapping failure preserves pages and records safe failure context" do
    fake = reader do |offset:, **_|
      if offset.zero?
        page(next_offset: 50)
      else
        raise Integrations::Rock::PersonMapper::MappingError.new(
          rock_id: 999, invalid_fields: ["Guid"]
        )
      end
    end
    Directory::Refresh.new(run: @run, reader: fake).call
    assert_equal "failed", @run.reload.status
    assert_equal "invalid_person_identity", @run.error_code
    assert_equal 1, @run.entries.count
    assert @run.resumable?
    assert_equal "read", @run.error_details["phase"]
    assert_equal 50, @run.error_details["offset"]
    assert_equal 999, @run.error_details["rock_id"]
    assert_equal ["Guid"], @run.error_details["fields"]
    assert_equal "Alex Example", person_profiles(:alex).reload.display_name
    @run.resume!
    Directory::Refresh.new(run: @run, reader: reader { |offset:, **_| page(people: [], offset: offset) }).call
    assert_equal "succeeded", @run.reload.status
    assert_equal 1, @run.imported_count
  end

  test "publication validation rolls back profiles and retries from preserved final staging" do
    nameless = Integrations::Rock::PersonRecord.new(**@person.to_h.merge(display_name: ""))
    Directory::Refresh.new(run: @run, reader: reader { |**_| page(people: [nameless]) }).call
    assert_equal "failed", @run.reload.status
    assert_equal "publication_validation_failed", @run.error_code
    assert_equal "publish", @run.error_details["phase"]
    assert_includes @run.error_details["fields"], "display_name"
    assert_equal 1, @run.entries.count
    assert @run.read_complete?
    assert_equal "Alex Example", person_profiles(:alex).reload.display_name
    entry = @run.entries.first
    entry.update!(payload: entry.payload.merge("display_name" => "Corrected Example"))
    @run.resume!
    Directory::Refresh.new(run: @run, reader: reader { |**_| flunk "must not redownload" }).call
    assert_equal "succeeded", @run.reload.status
    assert_equal "Corrected Example", person_profiles(:alex).reload.display_name
    assert_empty @run.entries
  end

  test "a repeated cursor fails safely without discarding previous pages" do
    fake = reader { |offset:, **_| page(offset: offset, next_offset: offset + 50) }
    Directory::Refresh.new(run: @run, reader: fake).call
    assert_equal "failed", @run.reload.status
    assert_equal "invalid_page_cursor", @run.error_code
    assert_equal 1, @run.page_count
    assert_equal 1, @run.entries.count
    assert_equal "read", @run.error_details["phase"]
  end

  test "failed duplicate checkpoint rolls back payload counts and cursor together" do
    updated = Integrations::Rock::PersonRecord.new(**@person.to_h.merge(
      rock_id: @person.rock_id + 1, display_name: "Updated Example"
    ))
    original = @run.method(:update!)
    interrupted = ->(**attributes) do
      raise "checkpoint interrupted" if attributes[:page_count] == 2
      original.call(**attributes)
    end
    fake = reader do |offset:, **_|
      offset.zero? ? page(next_offset: 50) : page(people: [updated], offset: 50)
    end
    @run.stub(:update!, interrupted) do
      assert_raises(RuntimeError) { Directory::Refresh.new(run: @run, reader: fake).call }
    end
    assert_equal 1, @run.reload.page_count
    assert_equal 0, @run.duplicate_count
    assert_equal @person.rock_id, @run.last_rock_id
    assert_equal @person.display_name, @run.entries.first.payload["display_name"]
    Directory::Refresh.new(run: @run, reader: fake).call
    assert_equal "succeeded", @run.reload.status
    assert_equal 1, @run.duplicate_count
  end

  test "HTTP failures record status and phase without storing upstream messages" do
    fake = reader do |**_|
      raise Integrations::Rock::ReadClient::ReadError.new("synthetic-private-upstream-body",
        http_status: 500, reason: "http_error")
    end
    Directory::Refresh.new(run: @run, reader: fake).call
    assert_equal "queued", @run.reload.status
    assert_equal 500, @run.error_details["http_status"]
    assert_equal "http_error", @run.error_details["reason"]
    assert_equal "read", @run.error_details["phase"]
    assert_not_includes @run.error_details.to_json, "synthetic-private-upstream-body"
  end

  test "source population mismatch preserves valid staging but does not publish the bad page" do
    fake = reader do |offset:, **_|
      raise Integrations::Rock::PeopleReader::InvalidPopulation if offset.positive?
      page(next_offset: 50)
    end
    Directory::Refresh.new(run: @run, reader: fake).call
    assert_equal "source_population_mismatch", @run.reload.error_code
    assert_equal 1, @run.entries.count
    assert_equal "Alex Example", person_profiles(:alex).reload.display_name
  end

  test "a crashed running job resumes rather than silently returning" do
    first = page(next_offset: 50)
    interrupted = reader do |offset:, **_|
      raise "worker interrupted" if offset == 50
      first
    end
    assert_raises(RuntimeError) { Directory::Refresh.new(run: @run, reader: interrupted).call }
    assert_equal "running", @run.reload.status
    assert_equal 1, @run.entries.count
    assert_equal 50, @run.next_offset
    last = page(people: [], offset: 50)
    resumed = reader do |offset:, **_|
      assert_equal 50, offset
      last
    end
    Directory::Refresh.new(run: @run, reader: resumed).call
    assert_equal "succeeded", @run.reload.status
    assert_equal 2, @run.page_count
  end

  test "entries and cursor roll back together if checkpointing is interrupted" do
    original = @run.method(:update!)
    interrupted = ->(**attributes) do
      raise "checkpoint interrupted" if attributes.key?(:page_count)
      original.call(**attributes)
    end
    @run.stub(:update!, interrupted) do
      assert_raises(RuntimeError) do
        Directory::Refresh.new(run: @run, reader: reader { |**_| page }).call
      end
    end
    assert_equal 0, @run.reload.next_offset
    assert_equal 0, @run.page_count
    assert_empty @run.entries
    Directory::Refresh.new(run: @run, reader: reader { |**_| page }).call
    assert_equal "succeeded", @run.reload.status
    assert_equal 1, @run.imported_count
  end

  test "a crash after the final checkpoint retries publication without reading Rock again" do
    PersonProfile.stub(:find_or_initialize_by, ->(**_) { raise "publication interrupted" }) do
      assert_raises(RuntimeError) do
        Directory::Refresh.new(run: @run, reader: reader { |**_| page }).call
      end
    end
    assert @run.reload.read_complete?
    assert_equal 1, @run.entries.count
    Directory::Refresh.new(run: @run, reader: reader { |**_| flunk "must not reread a completed import" }).call
    assert_equal "succeeded", @run.reload.status
    assert_equal 1, @run.imported_count
  end

  test "changed policy rejects publication and does not replace current people" do
    policy = @policy
    batch = page
    fake = reader do |**_|
      policy.update!(status: "draft", confirmed_at: nil, confirmed_by: nil)
      batch
    end
    Directory::Refresh.new(run: @run, reader: fake).call
    assert_equal "failed", @run.reload.status
    assert_equal "Alex Example", person_profiles(:alex).reload.display_name
  end

  test "town-only refresh cannot retain a street tied to a different Home location" do
    data = @person.to_h.merge(home_address: {
      status: "known", location_id: 999, city: "New Example Town", state: "ZZ", country: "US"
    }.freeze)
    scoped = Integrations::Rock::PersonRecord.new(**data)
    batch = page(people: [scoped])
    Directory::Refresh.new(run: @run, reader: reader { |**_| batch }).call
    profile = person_profiles(:alex).reload
    assert_equal "New Example Town", profile.city
    assert_empty profile.private_address
    assert_nil profile.private_observed_at
  end

  test "access changes invalidate retained staging instead of allowing publication or retry" do
    fake = reader do |offset:, **_|
      if offset.zero?
        page(next_offset: 50)
      else
        @actor.campus_accesses.destroy_all
        page(people: [], offset: 50)
      end
    end
    Directory::Refresh.new(run: @run, reader: fake).call
    assert_equal "access_or_policy_changed", @run.reload.error_code
    assert_empty @run.entries
    assert_not @run.checkpoint_retained?
    assert_not @run.resumable?
    assert_equal "Alex Example", person_profiles(:alex).reload.display_name
  end

  test "a second refresh cannot overlap an active run" do
    assert_raises(PersonRefreshRun::AlreadyRunning) { PersonRefreshRun.start!(actor: @actor) }
  end

  test "a recovered job cannot read while another database session owns the run" do
    config = PersonRefreshRun.connection_db_config.configuration_hash
    other = PG.connect(host: config[:host], port: config[:port], dbname: config[:database],
      user: config[:username], password: config[:password])
    key = "hashtextextended(#{PersonRefreshRun.connection.quote(@run.id)}, 73005001)"
    other.exec("SELECT pg_advisory_lock(#{key})")
    Directory::Refresh.new(run: @run, reader: reader { |**_| flunk "another worker owns this run" }).call
    assert_equal "queued", @run.reload.status
    assert_equal 0, @run.page_count
  ensure
    if other
      other.exec("SELECT pg_advisory_unlock(#{key})")
      other.close
    end
  end
end
