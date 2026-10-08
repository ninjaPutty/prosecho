module Directory
  class Refresh
    MAX_PAGES = 2000
    class PageError < StandardError; end

    def initialize(run:, reader: nil, page_size: ENV.fetch("ROCK_PERSON_PAGE_SIZE", "250"))
      @run = run
      @reader = reader
      @page_size = page_size
    end

    def call
      # A session lock prevents a recovered job from racing a worker that wakes
      # after sleep. PostgreSQL releases it if the worker/connection disappears.
      PersonRefreshRun.connection_pool.with_connection do |connection|
        key = "hashtextextended(#{connection.quote(@run.id)}, 73005001)"
        locked = connection.select_value("SELECT pg_try_advisory_lock(#{key})")
        next unless locked
        begin
          refresh
        ensure
          connection.select_value("SELECT pg_advisory_unlock(#{key})") if connection.active?
        end
      end
    end

    private

    def refresh
      @run.reload
      return unless @run.active?
      return if @run.retry_at&.future?
      @run.update!(status: "running", started_at: @run.started_at || Time.current,
        error_code: nil, retry_at: nil)
      @phase = "authorization"
      @publishing_rock_id = nil
      actor = @run.actor
      verify!(actor)
      reader = @reader || Integrations::Rock::PeopleReader.new(actor: actor,
        campus_ids: @run.campus_ids)
      until @run.read_complete?
        @phase = "read"
        raise PageError, "page_limit_exceeded" if @run.page_count >= MAX_PAGES
        offset = @run.next_offset
        page = reader.read_page(limit: page_size, offset: offset, after_id: @run.last_rock_id)
        valid = page.policy_revision == @run.policy_revision && page.offset == offset &&
          (page.next_offset.nil? || page.next_offset > offset)
        raise PageError, "invalid_page_contract" unless valid
        cursor = page.last_rock_id
        if (cursor && @run.last_rock_id && cursor <= @run.last_rock_id) ||
            (cursor.nil? && page.next_offset)
          raise PageError, "invalid_page_cursor"
        end
        # Entries and cursor commit together. An interrupted page is re-read;
        # completed pages are never discarded or inserted a second time.
        @run.with_lock do
          @phase = "checkpoint"
          people = page.people.index_by(&:rock_guid)
          existing = @run.entries.where(rock_guid: people.keys).count
          duplicates = page.people.size - people.size + existing
          if people.any?
            @run.entries.upsert_all(people.values.map do |person|
              {run_id: @run.id, rock_guid: person.rock_guid, payload: person.to_h.as_json,
               observed_at: page.observed_at}
            end, unique_by: [:run_id, :rock_guid])
          end
          @run.update!(page_count: @run.page_count + 1,
            checkpoint_retained: true, duplicate_count: @run.duplicate_count + duplicates,
            last_rock_id: cursor || @run.last_rock_id,
            next_offset: page.next_offset || offset, read_complete: page.next_offset.nil?,
            last_progress_at: Time.current)
        end
      end
      @phase = "publish"
      publish!(actor)
    rescue Integrations::Rock::ReadClient::ReadError => error
      @run.update!(status: "queued", error_code: "rock_read_failed",
        error_details: failure_details("rock_read_failed").merge(
          "http_status" => error.http_status, "reason" => error.reason
        ).compact,
        retry_at: 1.minute.from_now)
    rescue Integrations::Rock::ReadClient::ConfigurationError
      @run.update!(status: "queued", error_code: "rock_not_configured",
        error_details: failure_details("rock_not_configured"), retry_at: 1.minute.from_now)
    rescue Integrations::Rock::PeopleReader::InvalidPopulation
      fail!("source_population_mismatch")
    rescue Integrations::Rock::PeopleReader::NotAuthorized,
      Integrations::Rock::PeopleReader::PolicyNotReady, PersonRefreshRun::NotReady
      fail!("access_or_policy_changed")
      @run.entries.delete_all
      @run.update!(checkpoint_retained: false)
    rescue PageError => error
      fail!(error.message)
    rescue Integrations::Rock::PersonMapper::MappingError => error
      fail!("invalid_person_identity", "fields" => error.invalid_fields, "rock_id" => error.rock_id)
    rescue ActiveRecord::RecordInvalid => error
      code = (@phase == "publish") ? "publication_validation_failed" : "staging_validation_failed"
      fail!(code, "fields" => error.record.errors.attribute_names.map(&:to_s),
        "rock_id" => @publishing_rock_id)
    rescue ActiveRecord::RecordNotUnique
      code = (@phase == "publish") ? "publication_identity_conflict" : "staging_identity_conflict"
      fail!(code, "rock_id" => @publishing_rock_id)
    end

    def fail!(code, details = {})
      @run.update!(status: "failed", error_code: code,
        error_details: failure_details(code).merge(details).compact, finished_at: Time.current,
        retry_at: nil)
    end

    def failure_details(code)
      {"code" => code, "phase" => @phase || "authorization", "offset" => @run.next_offset,
       "page" => (@phase == "publish") ? @run.page_count : @run.page_count + 1,
       "last_rock_id" => @run.last_rock_id, "failed_at" => Time.current.iso8601}
    end

    def page_size
      value = Integer(@page_size.to_s, 10, exception: false)
      unless value&.between?(1, Integrations::Rock::ReadClient::MAX_PEOPLE_PAGE_SIZE)
        raise PageError, "invalid_page_size"
      end
      value
    end

    def publish!(actor)
      PersonProfile.transaction do
        PersonProfile.connection.execute("SELECT pg_advisory_xact_lock(73005000)")
        verify!(actor)
        policy = DataPolicy.current
        @run.entries.find_each do |entry|
          data = entry.payload
          @publishing_rock_id = data["rock_id"]
          campus_id = data.dig("campus", "id")
          raise PersonRefreshRun::NotReady unless @run.campus_ids.include?(campus_id)
          person = PersonProfile.find_or_initialize_by(source_system: "rock.chapel.org",
            rock_guid: entry.rock_guid)
          old_location = person.location_id
          old_policy = person.policy_revision
          home = data["home_address"] || {}
          person.assign_attributes(campus_id: campus_id, rock_id: data.fetch("rock_id"),
            first_name: data.dig("names", "first_name"), last_name: data.dig("names", "last_name"),
            nick_name: data.dig("names", "nick_name"), display_name: data.fetch("display_name"),
            birth_date: data["birth_date"],
            connection_status_id: data.dig("connection_status", "id"),
            connection_status_label: data.dig("connection_status", "label"),
            marital_status_id: data.dig("marital_status", "id"),
            marital_status_label: data.dig("marital_status", "label"),
            city: home["city"], state: home["state"], country: home["country"],
            home_status: home["status"] || "missing", location_id: home["location_id"],
            household: data["household"] || {}, custom_attributes: data["attributes"] || {},
            issues: data["issues"] || [], policy_revision: @run.policy_revision,
            observed_at: entry.observed_at, source_created_at: data["source_created_at"],
            source_modified_at: data["source_modified_at"], in_population: true, left_scope_at: nil)
          if actor.view_locations? && policy.selected_fields.include?("home_address")
            person.private_address = home.slice("street1", "street2", "postal_code",
              "latitude", "longitude")
            person.private_observed_at = entry.observed_at
          elsif old_location != person.location_id || old_policy != @run.policy_revision ||
              person.home_status != "known" || !policy.selected_fields.include?("home_address")
            person.private_address = {}
            person.private_observed_at = nil
          end
          if actor.view_photos? && policy.selected_fields.include?("photo")
            person.photo_id = data["photo_id"]
            person.photo_observed_at = entry.observed_at
          elsif old_policy != @run.policy_revision || !policy.selected_fields.include?("photo")
            person.photo_id = nil
            person.photo_observed_at = nil
          end
          person.save!
        end
        missing = PersonProfile.where(campus_id: @run.campus_ids, in_population: true)
          .where.not(rock_guid: @run.entries.select(:rock_guid))
        missing.update_all(in_population: false, left_scope_at: Time.current)
        cutoff = policy.profile_retention_days.days.ago
        PersonProfile.where(campus_id: @run.campus_ids, in_population: false)
          .where(left_scope_at: ...cutoff).delete_all
        @run.update!(status: "succeeded", imported_count: @run.entries.count,
          checkpoint_retained: false, finished_at: Time.current)
        @run.entries.delete_all
      end
    end

    def verify!(actor)
      actor.reload
      policy = DataPolicy.current
      allowed = actor.active? && !actor.access_locked? &&
        (@run.campus_ids - actor.campuses.active.pluck(:id)).empty?
      valid_policy = policy.confirmed? && policy.valid? && policy.revision == @run.policy_revision
      unless allowed && valid_policy
        raise PersonRefreshRun::NotReady, "Access or data decisions changed"
      end
    end
  end
end
