module Integrations
  module Rock
    class CampusImporter
      MAX_PAGES = 100
      PAGE_SIZE = 100
      class ImportError < StandardError; end

      def initialize(actor:, client: nil)
        @actor = actor
        @client = client
      end

      def call
        unless @actor&.reload&.administrator? && !@actor.access_locked?
          raise Access::Provisioner::NotAuthorized, "An active administrator is required"
        end
        @client ||= ReadClient.new
        records = fetch_catalog
        # Network reads finish before taking the local administration lock.
        Access::Provisioner.new(actor: @actor).import_campuses(records)
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
        raise ImportError, "Campus import failed. No changes were applied.", cause: nil
      end

      private

      def fetch_catalog
        rows = []
        MAX_PAGES.times do |page|
          batch = @client.campuses(limit: PAGE_SIZE, offset: page * PAGE_SIZE)
          unless batch.is_a?(Array) && batch.size <= PAGE_SIZE
            raise ImportError, "Rock returned an invalid campus catalog"
          end
          rows.concat(batch)
          return normalize(rows) if batch.size < PAGE_SIZE
        end
        raise ImportError, "The campus catalog exceeded the import page limit"
      end

      def normalize(rows)
        seen = Set.new
        rows.map do |row|
          valid = row.is_a?(Hash) && row["Id"].is_a?(Integer) &&
            row["Id"].between?(1, 2147483647) && row["Name"].is_a?(String) &&
            row["Name"].present? && [true, false].include?(row["IsActive"])
          unless valid && seen.add?(row["Id"])
            raise ImportError, "Rock returned invalid or duplicate campus records"
          end
          {rock_id: row["Id"], name: row["Name"].strip, active: row["IsActive"]}
        end
      end
    end
  end
end
