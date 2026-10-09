module Integrations
  module Rock
    class PeopleReader
      class NotAuthorized < StandardError; end
      class PolicyNotReady < StandardError; end
      class InvalidPopulation < NotAuthorized; end
      Page = Data.define(:people, :offset, :limit, :next_offset, :policy_revision, :observed_at) do
        def inspect
          "#<#{self.class.name} count=#{people.size}>"
        end

        def last_rock_id
          people.map(&:rock_id).max
        end
      end
      MAX_RELATED_PAGES = 10

      def initialize(actor:, client: nil, campus_ids: nil, import_run: nil, cache_limit: 1024)
        @actor = actor
        @client = client
        @requested_campus_ids = campus_ids
        @import_run = import_run
        @owns_client = client.nil?
        @addresses = FamilyCache.new(max_entries: cache_limit)
        @households = FamilyCache.new(max_entries: cache_limit)
      end

      def close
        @client.close if @owns_client && @client&.respond_to?(:close)
        @addresses.clear
        @households.clear
      end

      def read_page(limit: 25, offset: 0, after_id: nil)
        unless limit.is_a?(Integer) && limit.between?(1, ReadClient::MAX_PEOPLE_PAGE_SIZE) &&
            offset.is_a?(Integer) && offset.between?(0, 2147483647)
          raise ArgumentError, "Invalid people page limits"
        end
        scope = authorized_campuses
        policy = confirmed_policy
        revision = policy.revision
        fields = policy.selected_fields.dup
        fields.delete("photo") unless @import_run || @actor.view_photos?
        precise = @import_run ? true : @actor.view_locations?
        client = @client ||= ReadClient.new
        options = {campus_ids: scope.keys, fields: fields,
                   attribute_keys: policy.attribute_keys, limit: limit,
                   offset: after_id.nil? ? offset : 0}
        options[:after_id] = after_id unless after_id.nil?
        rows = client.people(**options)
        unless rows.is_a?(Array) && rows.size <= limit
          raise ReadClient::ReadError.new("Rock returned an invalid people page",
            reason: "invalid_people_page")
        end
        rows.each do |row|
          unless row.is_a?(Hash) && scope.key?(row["PrimaryCampusId"]) &&
              row["RecordTypeValueId"] == 1 && row["IsDeceased"] == false
            raise InvalidPopulation, "Rock returned a person outside the authorized population"
          end
        end
        verify_snapshot!(scope: scope, fields: fields, precise: precise, revision: revision)
        mapper = PersonMapper.new(fields: fields, attribute_keys: policy.attribute_keys,
          campuses: scope, precise: precise)
        families = rows.filter_map do |row|
          value = row["PrimaryFamilyId"]
          value if value.is_a?(Integer) && value.between?(1, 2147483647)
        end.uniq
        context = [@actor.id, revision, scope.keys.sort, fields.sort, precise]
        if @cache_context != context
          @addresses.clear
          @households.clear
          @cache_context = context
        end
        addresses = fields.include?("home_address") ?
          fetch_families(families, @addresses, ReadClient::MAX_HOME_FAMILY_BATCH,
            scope: scope, fields: fields, precise: precise, revision: revision) do |ids, page_offset|
            client.home_locations_for_families(ids, limit: 100, offset: page_offset, precise: precise)
          end : {}
        households = fields.include?("household") ?
          fetch_families(families, @households, ReadClient::MAX_MEMBER_FAMILY_BATCH,
            scope: scope, fields: fields, precise: precise, revision: revision, members: true) do |ids, page_offset, campuses|
            client.household_members_for_families(ids, limit: 100, offset: page_offset, campus_ids: campuses)
          end : {}
        people = rows.map do |row|
          family = row["PrimaryFamilyId"]
          family = nil unless family.is_a?(Integer) && family.between?(1, 2147483647)
          mapper.map(row, locations: addresses.fetch(family, []), members: households.fetch(family, []))
        end
        # Keep the source row count for pagination. Staging deduplicates GUIDs;
        # treating a repeated identity as a short page would truncate the scan.
        verify_snapshot!(scope: scope, fields: fields, precise: precise, revision: revision)
        AccessEvent.create!(actor: @actor, resource: "directory", outcome: "allowed")
        Page.new(people: people.freeze, offset: offset, limit: limit,
          next_offset: (rows.size == limit) ? offset + limit : nil,
          policy_revision: revision.freeze, observed_at: Time.current.freeze)
      rescue NotAuthorized
        if @actor&.persisted? && User.exists?(@actor.id)
          AccessEvent.create!(actor: @actor, resource: "directory", outcome: "denied")
        end
        raise
      end

      private

      def authorized_campuses
        unless @actor&.reload&.active? && !@actor.access_locked?
          raise NotAuthorized, "An active account is required"
        end
        if @import_run
          unless @import_run.persisted? && @import_run.actor_id == @actor.id &&
              @import_run.reload.active? && @import_run.checkpoint_authorized?
            raise NotAuthorized, "An authorized all-campus import run is required"
          end
          # Global ingestion uses the catalog, not the operator's viewing grants.
          # The captured run scope includes inactive campuses; viewers still use
          # current active campus grants at every directory endpoint.
          return Campus.where(id: @import_run.campus_ids).to_h do |campus|
            [campus.rock_id, {id: campus.id, name: campus.name}]
          end
        end
        campuses = @actor.campuses.active.to_a
        if @requested_campus_ids
          unless @requested_campus_ids.is_a?(Array) && @requested_campus_ids.any? &&
              (@requested_campus_ids - campuses.map(&:id)).empty?
            raise NotAuthorized, "Requested campuses are outside the authorized scope"
          end
          campuses = campuses.select { |campus| @requested_campus_ids.include?(campus.id) }
        end
        scope = campuses.to_h do |campus|
          [campus.rock_id, {id: campus.id, name: campus.name}]
        end
        raise NotAuthorized, "Explicit active campus access is required" if scope.empty?
        scope
      end

      def confirmed_policy
        policy = DataPolicy.current
        unless policy.persisted? && policy.confirmed? && policy.valid?
          raise PolicyNotReady, "Complete agreed data decisions are required"
        end
        policy
      end

      def fetch_families(families, cache, batch_size, scope:, fields:, precise:, revision:, members: false)
        result = families.to_h { |id| [id, cache.fetch(id)] }
        missing = families.select { |id| result[id].nil? }
        partitions = members ? scope.keys.each_slice(ReadClient::MAX_HOUSEHOLD_CAMPUS_SCOPE).to_a : [nil]
        missing.each_slice(batch_size) do |ids|
          collected = ids.to_h { |id| [id, []] }
          partitions.each do |campuses|
            rows = related_pages(max_pages: MAX_RELATED_PAGES * ids.size) do |offset|
              verify_snapshot!(scope: scope, fields: fields, precise: precise, revision: revision)
              batch = yield(ids, offset, campuses)
              unless batch.is_a?(Array) && batch.all? { |row| row.is_a?(Hash) && ids.include?(row["GroupId"]) }
                raise ReadClient::ReadError.new("Rock returned unrelated family records", reason: "invalid_related_scope")
              end
              batch
            end
            grouped = rows.group_by { |row| row["GroupId"] }
            ids.each do |id|
              values = grouped.fetch(id, [])
              if values.size > MAX_RELATED_PAGES * 100
                raise ReadClient::ReadError.new("Related records exceeded the family limit", reason: "related_page_limit")
              end
              collected[id].concat(values.map { |row| project_related(row, members: members, precise: precise) })
            end
          end
          verify_snapshot!(scope: scope, fields: fields, precise: precise, revision: revision)
          # Only fully paginated family results enter the cache, including empty
          # results. Page-local references survive LRU eviction during this page.
          ids.each do |id|
            result[id] = collected.fetch(id)
            cache.store(id, result[id])
          end
        end
        result
      end

      def project_related(row, members:, precise:)
        if members
          result = row.slice("Id", "GroupId", "PersonId", "GroupRoleId", "GroupMemberStatus", "IsArchived")
          result["GroupRole"] = row["GroupRole"].slice("Id", "Name") if row["GroupRole"].is_a?(Hash)
          result["Person"] = row["Person"].slice("Id", "Guid", "PrimaryCampusId") if row["Person"].is_a?(Hash)
        else
          result = row.slice("Id", "GroupId", "LocationId")
          if row["GroupLocationTypeValue"].is_a?(Hash)
            result["GroupLocationTypeValue"] = row["GroupLocationTypeValue"].slice("Value")
          end
          if row["Location"].is_a?(Hash)
            columns = %w[Id IsActive City State Country]
            columns += %w[Street1 Street2 PostalCode] if precise
            result["Location"] = row["Location"].slice(*columns)
          end
        end
        result
      end

      def related_pages(max_pages: MAX_RELATED_PAGES)
        rows = []
        max_pages.times do |page|
          batch = yield(page * 100)
          unless batch.is_a?(Array) && batch.size <= 100
            raise ReadClient::ReadError.new("Rock returned invalid related records",
              reason: "invalid_related_page")
          end
          rows.concat(batch)
          return rows if batch.size < 100
        end
        raise ReadClient::ReadError.new("Related records exceeded the page limit",
          reason: "related_page_limit")
      end

      def verify_snapshot!(scope:, fields:, precise:, revision:)
        current_scope = authorized_campuses
        allowed = (scope.keys - current_scope.keys).empty?
        unless @import_run
          allowed &&= @actor.view_locations? if precise
          allowed &&= @actor.view_photos? if fields.include?("photo")
        end
        raise NotAuthorized, "Access changed during the read" unless allowed
        unless confirmed_policy.revision == revision
          raise PolicyNotReady, "Data decisions changed during the read"
        end
      end
    end
  end
end
