module Directory
  class ChangeRecorder
    ADDRESS_FIELDS = %w[status location_id city state country street1 street2 postal_code].freeze

    def initialize(person:, run:, payload:, observed_at:, discovered_at:)
      @person, @run, @payload = person, run, payload
      @observed_at, @discovered_at = observed_at, discovered_at
    end

    def call
      snapshot = PersonSnapshot.find_or_initialize_by(person_profile: @person)
      current = state
      if snapshot.persisted? && snapshot.policy_revision == @run.policy_revision
        compare(snapshot, current)
      end
      snapshot.update!(campus: @person.campus, refresh_run: @run,
        policy_revision: @run.policy_revision, campus_scope: @run.campus_ids.sort,
        state: current, observed_at: @observed_at)
    end

    private

    def compare(snapshot, current)
      previous = snapshot.state
      {
        "connection_status" => "connection_status_changed",
        "home_address" => "home_address_changed"
      }.each do |field, type|
        next unless previous.key?(field) && current.key?(field) && previous[field] != current[field]
        record(snapshot, type, previous[field], current[field])
      end
      return unless snapshot.campus_scope.sort == @run.campus_ids.sort &&
        previous["household"] && current["household"]

      old = previous["household"]
      fresh = current["household"]
      family_changed = old["family_id"] != fresh["family_id"]
      old_members = old.fetch("members", []).index_by { |m| m["person_guid"] }
      known = old.fetch("seen_member_guids", old_members.keys)
      additions = fresh["members"].reject { |m| known.include?(m["person_guid"]) }
      roles = fresh["members"].select do |m|
        prior = old_members[m["person_guid"]]
        prior && prior["role"] != m["role"]
      end
      removed = if !family_changed && old["complete"] && fresh["complete"]
        old_members.values.reject do |m|
          fresh["members"].any? { |present| present["person_guid"] == m["person_guid"] }
        end
      else
        []
      end
      # Incomplete rosters cannot establish removals or make a returning member
      # look newly added. Remember identities until the household reference changes.
      unless family_changed || fresh["complete"]
        fresh["seen_member_guids"] = (known + fresh["seen_member_guids"]).uniq.sort
      end
      return unless family_changed || additions.any? || roles.any? || removed.any?

      record(snapshot, "family_composition_changed", old.except("seen_member_guids"),
        fresh.except("seen_member_guids"), details: {"added" => additions, "roles" => roles,
                                                     "removed" => removed},
        related_campus_rock_ids: (additions + roles + removed).map { |m| m["campus_rock_id"] }.uniq,
        household_reference_changed: family_changed)
    end

    def record(snapshot, type, previous, current, **extra)
      PersonChangeEvent.create!(person_profile: @person, refresh_run: @run,
        campus: @person.campus, previous_campus: snapshot.campus,
        source_system: @person.source_system, rock_guid: @person.rock_guid, rock_id: @person.rock_id,
        policy_revision: @run.policy_revision, event_type: type,
        previous_value: previous, current_value: current, discovered_at: @discovered_at, **extra)
    end

    def state
      result = {}
      result["connection_status"] = @payload["connection_status"].slice("id", "label") if @payload["connection_status"]
      result["home_address"] = @payload["home_address"].slice(*ADDRESS_FIELDS) if @payload["home_address"]
      if @payload["household"]
        source = @payload["household"]
        members = Array(source["members"]).map do |m|
          m.slice("person_guid", "campus_rock_id", "role")
        end.sort_by { |m| m["person_guid"] }
        result["household"] = {"family_id" => source["family_id"], "members" => members,
                               "scope" => source["scope"], "complete" => source["complete"],
                               "seen_member_guids" => members.map { |m| m["person_guid"] }}
      end
      result
    end
  end
end
