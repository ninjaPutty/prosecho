require "test_helper"
require "json"
require "minitest/mock"
require_relative "../support/directory_policy"

class PersonChangeRecordingTest < ActiveSupport::TestCase
  include DirectoryPolicy

  setup do
    @policy = confirm_directory_policy
    @actor = users(:administrator)
    @person = Integrations::Rock::PersonMapper.new(fields: DataPolicy::FIELD_LABELS.keys,
      campuses: {100001 => {id: campuses(:north).id, name: "Example North"}})
      .map(JSON.parse(file_fixture("rock_person.json").read))
  end

  def publish(person = @person)
    run = PersonRefreshRun.start!(actor: @actor)
    batch = Integrations::Rock::PeopleReader::Page.new(people: [person], offset: 0,
      limit: 250, next_offset: nil, policy_revision: @policy.reload.revision, observed_at: Time.current)
    reader = Object.new
    reader.define_singleton_method(:read_page) { |**_| batch }
    Directory::Refresh.new(run: run, reader: reader).call
    run.reload
  end

  test "first publication is quiet and repeated values create no duplicate events" do
    assert_equal "succeeded", publish.status
    assert_equal 1, PersonSnapshot.count
    assert_empty PersonChangeEvent.all
    assert_equal "succeeded", publish.status
    assert_empty PersonChangeEvent.all
    assert_equal 1, PersonSnapshot.count
  end

  test "status and structured address differences produce immutable UTC discovery events" do
    publish
    changed = Integrations::Rock::PersonRecord.new(**@person.to_h.merge(
      connection_status: {id: 202, label: "Updated connection"},
      home_address: {status: "known", location_id: 999, city: "New Example Town",
                     street1: "20 Fixture Lane", postal_code: "00000"}
    ))
    run = publish(changed)
    assert_equal "succeeded", run.status
    assert_equal 2, PersonChangeEvent.count
    status = PersonChangeEvent.find_by!(event_type: "connection_status_changed")
    assert_equal "Example connection", status.previous_value["label"]
    assert_equal "Updated connection", status.current_value["label"]
    assert_equal run.id, status.refresh_run_id
    assert status.discovered_at >= run.started_at
    assert_raises(ActiveRecord::ReadOnlyRecord) { status.update!(details: {"changed" => true}) }
    publish(changed)
    assert_equal 2, PersonChangeEvent.count
  end

  test "incomplete or failed publication never advances snapshots or leaves events" do
    publish
    baseline = PersonSnapshot.first.state
    invalid = Integrations::Rock::PersonRecord.new(**@person.to_h.merge(
      display_name: "", connection_status: {id: 202, label: "Updated connection"}
    ))
    run = publish(invalid)
    assert_equal "failed", run.status
    assert_equal baseline, PersonSnapshot.first.state
    assert_empty PersonChangeEvent.all
    assert_equal 1, run.entries.count
  end

  test "policy revision establishes a fresh quiet baseline rather than inferring changes" do
    publish
    @policy.update!(history_retention_days: 180)
    changed = Integrations::Rock::PersonRecord.new(**@person.to_h.merge(
      connection_status: {id: 202, label: "Updated connection"}
    ))
    publish(changed)
    assert_empty PersonChangeEvent.all
    assert_equal @policy.revision, PersonSnapshot.first.policy_revision
  end

  test "incomplete household disappearance and return do not assert removals or new additions" do
    member = {person_guid: "00000000-0000-4000-8000-000000000202",
              campus_rock_id: 100001, role: {id: 11, label: "Child"}}
    populated = Integrations::Rock::PersonRecord.new(**@person.to_h.merge(
      household: {family_id: 301, members: [member], scope: "authorized_campuses", complete: false}
    ))
    publish(populated)
    publish(@person)
    publish(populated)
    assert_empty PersonChangeEvent.all
    additional = member.merge(person_guid: "00000000-0000-4000-8000-000000000203")
    expanded = Integrations::Rock::PersonRecord.new(**populated.to_h.merge(
      household: populated.household.merge(members: [member, additional])
    ))
    publish(expanded)
    event = PersonChangeEvent.find_by!(event_type: "family_composition_changed")
    assert_equal 1, event.details["added"].size
    assert_empty event.details["roles"]
    assert_empty event.details["removed"]
  end

  test "common member role changes are factual and removals require two complete comparable rosters" do
    member = {person_guid: "00000000-0000-4000-8000-000000000202",
              campus_rock_id: 100001, role: {id: 11, label: "Child"}}
    person = Integrations::Rock::PersonRecord.new(**@person.to_h.merge(
      household: {family_id: 301, members: [member], scope: "authorized_campuses", complete: true}
    ))
    publish(person)
    changed = Integrations::Rock::PersonRecord.new(**person.to_h.merge(
      household: person.household.merge(members: [member.merge(role: {id: 12, label: "Adult"})])
    ))
    publish(changed)
    assert_equal 1, PersonChangeEvent.first.details["roles"].size
    empty = Integrations::Rock::PersonRecord.new(**changed.to_h.merge(
      household: changed.household.merge(members: [])
    ))
    publish(empty)
    assert_equal 2, PersonChangeEvent.count
    assert_equal 1, PersonChangeEvent.order(:created_at).last.details["removed"].size
  end

  test "failure after event insertion rolls back the event and projection together" do
    publish
    before = PersonSnapshot.first.state
    changed = Integrations::Rock::PersonRecord.new(**@person.to_h.merge(
      connection_status: {id: 202, label: "Updated connection"}
    ))
    original = PersonChangeEvent.method(:create!)
    insert_then_fail = ->(**attributes) do
      original.call(attributes)
      invalid = PersonProfile.new
      invalid.errors.add(:display_name, "synthetic-private-error")
      raise ActiveRecord::RecordInvalid, invalid
    end
    PersonChangeEvent.stub(:create!, insert_then_fail) do
      assert_equal "failed", publish(changed).status
    end
    assert_empty PersonChangeEvent.all
    assert_equal before, PersonSnapshot.first.state
    assert_equal @person.connection_status[:label], PersonProfile.find_by!(rock_guid: @person.rock_guid).connection_status_label
  end

  test "catalog scope changes reset household comparison and coordinate updates are not address changes" do
    publish
    Campus.create!(name: "New Example", rock_id: 100003)
    member = {person_guid: "00000000-0000-4000-8000-000000000202",
              campus_rock_id: 100003, role: {id: 11, label: "Child"}}
    changed = Integrations::Rock::PersonRecord.new(**@person.to_h.merge(
      household: @person.household.merge(members: [member]),
      home_address: @person.home_address.merge(latitude: 42.0, longitude: -88.0)
    ))
    publish(changed)
    assert_empty PersonChangeEvent.all
  end

  test "snapshot and event inspection redact retained private values" do
    snapshot = PersonSnapshot.new(state: {"street1" => "synthetic-private-address"})
    event = PersonChangeEvent.new(previous_value: {"street1" => "synthetic-private-address"},
      current_value: {"street1" => "synthetic-new-private-address"})
    assert_not_includes snapshot.inspect, "synthetic-private-address"
    assert_not_includes event.inspect, "synthetic-private-address"
    assert_not_includes event.inspect, "synthetic-new-private-address"
  end

  test "successful publication applies history retention and profile deletion does not erase retained events" do
    run = publish
    profile = PersonProfile.find_by!(rock_guid: @person.rock_guid)
    old = PersonChangeEvent.create!(person_profile: profile, refresh_run: run,
      campus: profile.campus, previous_campus: profile.campus,
      source_system: profile.source_system, rock_guid: profile.rock_guid, rock_id: profile.rock_id,
      policy_revision: @policy.revision, event_type: "connection_status_changed",
      discovered_at: 366.days.ago)
    publish
    assert_not PersonChangeEvent.exists?(old.id)
    recent = PersonChangeEvent.create!(person_profile: profile, refresh_run: run,
      campus: profile.campus, previous_campus: profile.campus,
      source_system: profile.source_system, rock_guid: profile.rock_guid, rock_id: profile.rock_id,
      policy_revision: @policy.revision, event_type: "connection_status_changed",
      discovered_at: Time.current)
    PersonProfile.where(id: profile.id).delete_all
    assert_nil recent.reload.person_profile_id
    assert PersonChangeEvent.exists?(recent.id)
    assert_not PersonSnapshot.exists?(person_profile_id: profile.id)
  end

  test "SQL bind logging does not print private snapshot or event addresses" do
    output = StringIO.new
    original_logger = ActiveRecord::Base.logger
    ActiveRecord::Base.logger = ActiveSupport::Logger.new(output)
    publish
    changed = Integrations::Rock::PersonRecord.new(**@person.to_h.merge(
      home_address: {status: "known", location_id: 999, city: "Example Town",
                     street1: "synthetic-private-address"}
    ))
    assert_equal "succeeded", publish(changed).status
    assert_not output.string.include?("synthetic-private-address"), "Private staging/history value leaked to SQL logging"
  ensure
    ActiveRecord::Base.logger = original_logger
  end
end
