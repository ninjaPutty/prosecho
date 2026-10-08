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

      def initialize(actor:, client: nil, campus_ids: nil, import_run: nil)
        @actor = actor
        @client = client
        @requested_campus_ids = campus_ids
        @import_run = import_run
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
        client = @client || ReadClient.new
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
        addresses = {}
        households = {}
        people = rows.map do |row|
          family = row["PrimaryFamilyId"]
          family = nil unless family.is_a?(Integer) && family.between?(1, 2147483647)
          locations = if family && fields.include?("home_address")
            addresses[family] ||= related_pages do |page_offset|
              verify_snapshot!(scope: scope, fields: fields, precise: precise, revision: revision)
              client.home_locations(family, limit: 100, offset: page_offset, precise: precise)
            end
          else
            []
          end
          members = if family && fields.include?("household")
            # Rock's OData node limit rejects a long Person/PrimaryCampusId OR
            # filter. Paginate each campus partition fully before combining it.
            households[family] ||= scope.keys.each_slice(ReadClient::MAX_HOUSEHOLD_CAMPUS_SCOPE)
              .flat_map do |campus_ids|
              related_pages do |page_offset|
                verify_snapshot!(scope: scope, fields: fields, precise: precise, revision: revision)
                client.household_members(family, limit: 100,
                  offset: page_offset, campus_ids: campus_ids)
              end
            end
          else
            []
          end
          mapper.map(row, locations: locations, members: members)
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

      def related_pages
        rows = []
        MAX_RELATED_PAGES.times do |page|
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
