require "json"
require "net/http"
require "uri"

module Integrations
  module Rock
    class ReadClient
      BASE_URL = "https://rock.chapel.org"
      MAX_PEOPLE_PAGE_SIZE = 500
      class ConfigurationError < StandardError; end

      class ReadError < StandardError
        attr_reader :http_status, :reason

        def initialize(message = "Rock read failed", http_status: nil, reason: "read_failure")
          @http_status = http_status
          @reason = reason
          super(message)
        end
      end
      Photo = Data.define(:body, :content_type) do
        def inspect
          "#<#{self.class.name} image=true>"
        end
      end
      PHOTO_TYPES = %w[image/jpeg image/png image/webp image/gif].freeze
      MAX_PHOTO_BYTES = 2 * 1024 * 1024

      def initialize(api_key: ENV["ROCK_API_KEY"], base_url: BASE_URL, transport: nil)
        unless base_url == BASE_URL && api_key.is_a?(String) && api_key.present?
          raise ConfigurationError, "A runtime Rock key and the configured Chapel host are required"
        end
        @api_key = api_key
        @base_url = base_url
        @transport = transport || method(:perform_get)
      end

      def campuses(limit: 100, offset: 0)
        get_resource("Campuses", "$orderby" => "Id", "$select" => "Id,Name,IsActive",
          "$top" => page_limit(limit), "$skip" => page_offset(offset))
      end

      def home_locations(family_id, limit: 100, offset: 0, precise: true)
        raise ArgumentError, "Invalid address permission" unless [true, false].include?(precise)
        columns = %w[Id LocationId GroupLocationTypeValue/Value Location/Id Location/IsActive
          Location/City Location/State Location/Country]
        if precise
          # Chapel's v1 OData coordinate projection returns HTTP 500 even when
          # the same Home address reads successfully. Keep addresses usable;
          # coordinates need a separately verified map-phase read path.
          columns += %w[Location/Street1 Location/Street2 Location/PostalCode]
        end
        get_resource("GroupLocations", "$filter" => "GroupId eq #{identifier(family_id)} " \
          "and GroupLocationTypeValue/Value eq 'Home'", "$orderby" => "Id",
          "$select" => columns.join(","),
          "$expand" => "Location,GroupLocationTypeValue",
          "$top" => page_limit(limit), "$skip" => page_offset(offset))
      end

      def household_members(family_id, limit: 100, offset: 0, campus_ids: nil)
        # Rock v1 exposes the enum as Edm.String to OData but serializes it as
        # an integer in JSON. Numeric `eq 1` fails; the named string is accepted.
        filter = "GroupId eq #{identifier(family_id)} and IsArchived eq false " \
          "and GroupMemberStatus eq 'Active'"
        parameters = {"$filter" => filter, "$orderby" => "Id", "$expand" => "GroupRole",
                      "$top" => page_limit(limit), "$skip" => page_offset(offset)}
        if campus_ids
          parameters["$filter"] += " and #{campus_filter(campus_ids, prefix: "Person/")}"
          parameters["$expand"] = "GroupRole,Person"
          parameters["$select"] = %w[Id PersonId GroupRoleId GroupMemberStatus IsArchived
            GroupRole/Id GroupRole/Name Person/Id Person/Guid Person/PrimaryCampusId].join(",")
        end
        get_resource("GroupMembers", parameters)
      end

      def inspect
        "#<#{self.class.name} read_only=true>"
      end

      def person(id)
        get_resource("People/#{identifier(id)}")
      end

      def photo(id)
        uri = URI("#{@base_url}/GetImage.ashx")
        uri.query = URI.encode_www_form(id: identifier(id), maxwidth: 160, maxheight: 160)
        request = Net::HTTP::Get.new(uri)
        request["Authorization-Token"] = @api_key
        request["User-Agent"] = "Prosecho private Rock portrait reader"
        body = +"".b
        content_type = nil
        Net::HTTP.start(uri.host, uri.port, use_ssl: true,
          open_timeout: 5, read_timeout: 15, write_timeout: 5) do |http|
          http.request(request) do |response|
            unless response.is_a?(Net::HTTPSuccess)
              raise ReadError, "Rock portrait unavailable"
            end
            content_type = response["Content-Type"].to_s.split(";").first
            raise ReadError, "Unsupported Rock portrait type" unless PHOTO_TYPES.include?(content_type)
            response.read_body do |chunk|
              if body.bytesize + chunk.bytesize > MAX_PHOTO_BYTES
                raise ReadError, "Rock portrait exceeded size limit"
              end
              body << chunk
            end
          end
        end
        Photo.new(body: body.freeze, content_type: content_type.freeze)
      rescue SocketError, IOError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError
        raise ReadError, "Rock portrait could not be read", cause: nil
      end

      def people(campus_ids:, fields:, attribute_keys: [], limit: 25, offset: 0, after_id: nil)
        raise ArgumentError, "Invalid person attribute keys" unless attribute_keys.is_a?(Array)
        columns = PersonFields.columns(fields)
        expansions = PersonFields.expansions(fields)
        parameters = {
          "$filter" => "#{campus_filter(campus_ids)} and IsDeceased eq false " \
            "and RecordTypeValueId eq 1",
          "$orderby" => "Id", "$top" => page_limit(limit, maximum: MAX_PEOPLE_PAGE_SIZE),
          "$skip" => page_offset(offset)
        }
        unless after_id.nil?
          cursor = page_offset(after_id)
          raise ArgumentError, "Invalid source ID cursor" if cursor > 2147483647
          parameters["$filter"] += " and Id gt #{cursor}"
          parameters["$skip"] = 0
        end
        if attribute_keys.any?
          valid = attribute_keys.is_a?(Array) && attribute_keys.size <= 100 &&
            attribute_keys.all? do |key|
              key.is_a?(String) && key.match?(/\A[A-Za-z0-9_.:-]{1,100}\z/)
            end
          raise ArgumentError, "Invalid person attribute keys" unless valid
          parameters["loadAttributes"] = "simple"
          parameters["attributeKeys"] = attribute_keys.uniq.join(",")
          columns << "AttributeValues"
        end
        parameters["$select"] = columns.join(",")
        parameters["$expand"] = expansions.join(",") if expansions.any?
        get_resource("People", parameters)
      end

      def read_only?
        true
      end

      private

      def campus_filter(ids, prefix: "")
        unless ids.is_a?(Array) && ids.any? && ids.size <= 100
          raise ArgumentError, "Explicit campus scope of 1-100 campuses is required"
        end
        values = ids.map { |id| identifier(id) }.uniq.sort
        "(#{values.map { |id| "#{prefix}PrimaryCampusId eq #{id}" }.join(" or ")})"
      end

      # Named methods construct only these known read paths. Rock also has GET
      # actions that mutate, so rejecting HTTP mutation verbs alone is insufficient.
      def get_resource(resource, parameters = {})
        uri = URI("#{@base_url}/api/#{resource}")
        uri.query = URI.encode_www_form(parameters) if parameters.any?
        request = Net::HTTP::Get.new(uri)
        request["Authorization-Token"] = @api_key
        request["Accept"] = "application/json"
        request["User-Agent"] = "Prosecho read-only Rock adapter"
        @transport.call(request)
      end

      def identifier(value)
        string = value.to_s
        unless string.match?(/\A[0-9]{1,10}\z/) && string.to_i.between?(1, 2147483647)
          raise ArgumentError, "Rock IDs must be positive 32-bit integers"
        end
        string.to_i
      end

      def page_limit(value, maximum: 100)
        unless value.is_a?(Integer) && value.between?(1, maximum)
          raise ArgumentError, "Limit must be 1-#{maximum}"
        end
        value
      end

      def page_offset(value)
        unless value.is_a?(Integer) && value.between?(0, 2147483647)
          raise ArgumentError, "Offset must be a nonnegative 32-bit integer"
        end
        value
      end

      def perform_get(request)
        response = Net::HTTP.start(request.uri.host, request.uri.port, use_ssl: true,
          open_timeout: 5, read_timeout: 15, write_timeout: 5) { |http| http.request(request) }
        # Never follow redirects or reflect an upstream body/URL in exception messages.
        unless response.is_a?(Net::HTTPSuccess)
          raise ReadError.new("Rock read failed (HTTP #{response.code})",
            http_status: response.code.to_i, reason: "http_error")
        end

        JSON.parse(response.body)
      rescue JSON::ParserError
        raise ReadError.new("Rock returned an invalid JSON response", reason: "invalid_json"), cause: nil
      rescue SocketError, IOError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError
        raise ReadError.new("Rock read could not be completed", reason: "network_error"), cause: nil
      end
    end
  end
end
