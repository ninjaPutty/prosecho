require "json"
require "net/http"
require "uri"

module Integrations
  module ChurchNext
    class Client
      class ConfigurationError < StandardError; end
      class RequestError < StandardError; end
      Photo = Data.define(:body, :content_type) do
        def inspect
          "#<#{self.class.name} image=true>"
        end
      end
      PHOTO_TYPES = %w[image/jpeg image/png image/webp image/gif].freeze

      def initialize(base_url: ENV["CHURCHNEXT_BASE_URL"], token: ENV["CHURCHNEXT_CALLBACK_TOKEN"], transport: nil)
        @origin = URI.parse(base_url.to_s)
        valid = @origin.scheme == "https" && @origin.host.present? && @origin.port == 443 &&
          @origin.userinfo.nil? && @origin.query.nil? && @origin.fragment.nil? &&
          ["", "/"].include?(@origin.path) && token.is_a?(String) &&
          token.match?(/\A[\x21-\x7E]{32,1024}\z/)
        raise ConfigurationError unless valid

        @token, @transport = token, transport
      rescue URI::InvalidURIError
        raise ConfigurationError
      end

      def notify_link(payload)
        uri = endpoint("/api/v1/prosecho/account_links")
        request = Net::HTTP::Post.new(uri)
        request["Accept"] = "application/json"
        request["Content-Type"] = "application/json"
        request.body = payload.to_json
        perform(uri, request) do |response|
          body = JSON.parse(read_body(response, 16.kilobytes))
          unless body.is_a?(Hash) && body["linked"] == true &&
              body["event_id"] == payload[:event_id] &&
              body["church_next_user_id"] == payload[:church_next_user_id]
            raise RequestError, "invalid_acknowledgement"
          end
        end
      rescue JSON::ParserError
        raise RequestError, "invalid_acknowledgement", cause: nil
      end

      def photo(user_id)
        unless user_id.is_a?(String) && user_id.match?(/\A[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}\z/)
          raise ArgumentError, "Invalid ChurchNext identifier"
        end
        uri = endpoint("/api/v1/prosecho/accounts/#{URI.encode_www_form_component(user_id)}/photo")
        request = Net::HTTP::Get.new(uri)
        request["Accept"] = PHOTO_TYPES.join(", ")
        perform(uri, request) do |response|
          type = response["content-type"].to_s.split(";").first
          raise RequestError, "unsupported_image" unless PHOTO_TYPES.include?(type)
          Photo.new(body: read_body(response, 2.megabytes), content_type: type)
        end
      end

      private

      def endpoint(path)
        @origin.dup.tap { |uri| uri.path = path }
      end

      def perform(uri, request, &block)
        request["Authorization"] = "Bearer #{@token}"
        request["User-Agent"] = "Prosecho ChurchNext linking client"
        receive = lambda do |response|
          raise RequestError, "http_#{response.code.to_i}" unless response.code.to_i == 200
          block.call(response)
        end
        # Only two fixed endpoint shapes are exposed. Redirects are never followed
        # and credentials never travel to a host supplied in the incoming payload.
        if @transport
          @transport.call(uri, request, &receive)
        else
          Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5,
            read_timeout: 5, write_timeout: 5, max_retries: 0) do |http|
            http.request(request, &receive)
          end
        end
      rescue Timeout::Error, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError,
        Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Net::ProtocolError
        raise RequestError, "network_unavailable", cause: nil
      end

      def read_body(response, maximum)
        body = +"".b
        response.read_body do |chunk|
          raise RequestError, "response_too_large" if body.bytesize + chunk.bytesize > maximum
          body << chunk
        end
        body
      end
    end
  end
end
