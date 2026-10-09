module Integrations
  module Rock
    class FamilyCache
      def initialize(max_entries: 1024, max_rows: 10_000)
        unless max_entries.is_a?(Integer) && max_entries.positive? &&
            max_rows.is_a?(Integer) && max_rows.positive?
          raise ArgumentError, "Positive family cache bounds are required"
        end
        @max_entries, @max_rows = max_entries, max_rows
        clear
      end

      def clear
        @entries = {}
        @rows = 0
      end

      def fetch(key)
        value = @entries.delete(key)
        @entries[key] = value if value
        value
      end

      def inspect
        "#<#{self.class.name} entries=#{@entries.size} rows=#{@rows}>"
      end

      def store(key, rows)
        previous = @entries.delete(key)
        @rows -= previous.size if previous
        return if rows.size > @max_rows
        while @entries.size >= @max_entries || @rows + rows.size > @max_rows
          _, removed = @entries.shift
          @rows -= removed.size
        end
        @entries[key] = immutable(rows)
        @rows += rows.size
      end

      private

      def immutable(value)
        case value
        when Hash then value.transform_values { |item| immutable(item) }.freeze
        when Array then value.map { |item| immutable(item) }.freeze
        when String then value.dup.freeze
        else value.freeze
        end
      end
    end
  end
end
