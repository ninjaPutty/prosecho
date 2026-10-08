require "date"

module Integrations
  module Rock
    class PersonMapper
      class MappingError < StandardError
        attr_reader :invalid_fields, :rock_id

        def initialize(message = "Rock returned an invalid person identity or campus",
          rock_id: nil, invalid_fields: [])
          @invalid_fields = invalid_fields
          @rock_id = rock_id
          super(message)
        end
      end
      GUID_PATTERN = /\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/i

      def initialize(fields:, campuses:, attribute_keys: [], today: Date.current, precise: true)
        PersonFields.validate!(fields)
        @fields = fields.dup.freeze
        @attribute_keys = attribute_keys.dup.freeze
        @campuses = campuses
        @today = today
        @precise = precise
      end

      def map(row, locations: [], members: [])
        raise MappingError.new(invalid_fields: ["record_shape"]) unless row.is_a?(Hash)
        invalid = []
        invalid << "Id" unless positive_id?(row["Id"])
        invalid << "Guid" unless valid_guid?(row["Guid"])
        invalid << "PrimaryCampusId" unless @campuses.key?(row["PrimaryCampusId"])
        if invalid.any?
          raise MappingError.new(rock_id: positive_id?(row["Id"]) ? row["Id"] : nil,
            invalid_fields: invalid)
        end
        issues = []
        names = {
          first_name: selected?("first_name") ? text(row["FirstName"]) : nil,
          last_name: selected?("last_name") ? text(row["LastName"]) : nil,
          nick_name: selected?("nick_name") ? text(row["NickName"]) : nil
        }
        preferred = names[:nick_name] || names[:first_name]
        display_name = [preferred, names[:last_name]].compact.join(" ")
        if display_name.blank?
          display_name = PersonRecord.unknown_name(row["Id"])
          issues << "person_name_missing"
        end
        birth = selected?("birth_date") ? birth_date(row, issues) : nil
        campus = @campuses.fetch(row["PrimaryCampusId"]).merge(rock_id: row["PrimaryCampusId"])
        connection = selected?("connection_status") ? lookup(row, "ConnectionStatusValue") : nil
        PersonRecord.new(rock_id: row["Id"], rock_guid: row["Guid"].downcase.freeze,
          campus: immutable(campus),
          names: immutable(names), display_name: display_name.freeze,
          birth_date: birth&.freeze, age: birth ? age(birth) : nil,
          connection_status: connection,
          marital_status: selected?("marital_status") ? lookup(row, "MaritalStatusValue") : nil,
          photo_id: (selected?("photo") && positive_id?(row["PhotoId"])) ? row["PhotoId"] : nil,
          home_address: selected?("home_address") ? address(row, locations, issues) : nil,
          household: selected?("household") ? household(row, members, issues) : nil,
          attributes: attributes(row), source_created_at: text(row["CreatedDateTime"]),
          source_modified_at: text(row["ModifiedDateTime"]), issues: immutable(issues))
      end

      private

      def address(row, locations, issues)
        empty = {status: "missing", location_id: nil, city: nil, state: nil, country: nil,
                 street1: nil, street2: nil, postal_code: nil, latitude: nil, longitude: nil}
        homes = locations.select do |entry|
          entry.is_a?(Hash) && entry.dig("GroupLocationTypeValue", "Value") == "Home" &&
            entry["Location"].is_a?(Hash) && entry["Location"]["IsActive"] != false &&
            positive_id?(entry["LocationId"])
        end.uniq { |entry| entry["LocationId"] }
        if homes.empty?
          issues << "home_address_missing"
          return immutable(empty)
        end
        if homes.size > 1
          issues << "home_address_ambiguous"
          return immutable(empty.merge(status: "ambiguous"))
        end
        entry = homes.first
        location = entry["Location"]
        values = empty.merge(status: "known", location_id: entry["LocationId"],
          city: text(location["City"]), state: text(location["State"]),
          country: text(location["Country"]))
        if @precise
          values.merge!(street1: text(location["Street1"]), street2: text(location["Street2"]),
            postal_code: text(location["PostalCode"]))
          lat, lon = location.values_at("Latitude", "Longitude")
          if lat.is_a?(Numeric) && lon.is_a?(Numeric) && lat.finite? && lon.finite? &&
              lat.between?(-90, 90) && lon.between?(-180, 180)
            values[:latitude] = lat
            values[:longitude] = lon
          end
        end
        immutable(values)
      end

      def age(birth)
        before_birthday = ([@today.month, @today.day] <=> [birth.month, birth.day]).negative?
        @today.year - birth.year - (before_birthday ? 1 : 0)
      end

      def attributes(row)
        source = row["AttributeValues"].is_a?(Hash) ? row["AttributeValues"] : {}
        values = @attribute_keys.to_h do |key|
          value = source[key]
          value = value["Value"] if value.is_a?(Hash)
          [key, value.is_a?(String) ? value.dup : nil]
        end
        immutable(values)
      end

      def birth_date(row, issues)
        values = row.values_at("BirthYear", "BirthMonth", "BirthDay")
        unless values.all? { |value| value.is_a?(Integer) }
          issues << (values.all?(&:nil?) ? "birth_date_missing" : "birth_date_partial")
          return nil
        end
        unless values.first.positive?
          issues << "birth_date_invalid"
          return nil
        end
        birth = Date.new(*values)
        if birth > @today
          issues << "birth_date_invalid"
          return nil
        end
        birth
      rescue Date::Error
        issues << "birth_date_invalid"
        nil
      end

      def household(row, members, issues)
        entries = members.filter_map do |member|
          next unless member.is_a?(Hash) && member["IsArchived"] == false &&
            member["GroupMemberStatus"] == 1 && member["Person"].is_a?(Hash)

          person = member["Person"]
          unless @campuses.key?(person["PrimaryCampusId"])
            issues << "household_members_outside_scope"
            next
          end
          unless valid_guid?(person["Guid"])
            issues << "household_member_identity_unknown"
            next
          end
          {person_guid: person["Guid"].downcase,
           campus_rock_id: person["PrimaryCampusId"],
           role: lookup(member, "GroupRole", label_key: "Name")}
        end.uniq { |entry| entry[:person_guid] }.sort_by { |entry| entry[:person_guid] }
        immutable(family_id: positive_id?(row["PrimaryFamilyId"]) ? row["PrimaryFamilyId"] : nil,
          members: entries, scope: "authorized_campuses", complete: false)
      end

      def immutable(value)
        case value
        when Hash then value.transform_values { |item| immutable(item) }.freeze
        when Array then value.map { |item| immutable(item) }.freeze
        when String then value.dup.freeze
        else value.freeze
        end
      end

      def lookup(row, key, label_key: "Value")
        id = row["#{key}Id"]
        source = row[key]
        label = (source.is_a?(Hash) && source["Id"] == id) ? text(source[label_key]) : nil
        immutable(id: positive_id?(id) ? id : nil, label: label)
      end

      def positive_id?(value)
        value.is_a?(Integer) && value.between?(1, 2147483647)
      end

      def selected?(field)
        @fields.include?(field)
      end

      def text(value)
        value.is_a?(String) ? value.strip.presence&.freeze : nil
      end

      def valid_guid?(value)
        value.is_a?(String) && value.match?(GUID_PATTERN)
      end
    end
  end
end
