require "json"
require "net/http"
require "uri"

module Integrations
  module Rock
    class ReadClient
      BASE_URL = "https://rock.chapel.org"
      class ConfigurationError < StandardError; end
      class ReadError < StandardError; end

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

      def home_locations(family_id, limit: 100, offset: 0)
        get_resource("GroupLocations", "$filter" => "GroupId eq #{identifier(family_id)}",
          "$expand" => "Location,GroupLocationTypeValue",
          "$top" => page_limit(limit), "$skip" => page_offset(offset))
      end

      def household_members(family_id, limit: 100, offset: 0)
        get_resource("GroupMembers",
          "$filter" => "GroupId eq #{identifier(family_id)} and IsArchived eq false",
          "$expand" => "GroupRole", "$top" => page_limit(limit), "$skip" => page_offset(offset))
      end

      def inspect
        "#<#{self.class.name} read_only=true>"
      end

      def person(id)
        get_resource("People/#{identifier(id)}")
      end

      def read_only?
        true
      end

      private

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

      def page_limit(value)
        unless value.is_a?(Integer) && value.between?(1, 100)
          raise ArgumentError, "Limit must be 1-100"
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
          raise ReadError, "Rock read failed (HTTP #{response.code})"
        end

        JSON.parse(response.body)
      rescue JSON::ParserError
        raise ReadError, "Rock returned an invalid JSON response", cause: nil
      rescue IOError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError
        raise ReadError, "Rock read could not be completed", cause: nil
      end
    end
  end
end
