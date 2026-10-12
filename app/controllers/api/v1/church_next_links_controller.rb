require "digest"

module Api
  module V1
    class ChurchNextLinksController < ActionController::API
      FIELDS = %w[church_next_user_id email email_verified first_name last_name photo_available].freeze
      MAX_BODY_BYTES = 16 * 1024

      before_action :private_response
      rate_limit to: 60, within: 1.minute, with: -> { render json: {error: "rate_limited"}, status: :too_many_requests }
      before_action :authenticate_integration

      def create
        return render_error("json_required", :unsupported_media_type) unless request.media_type == "application/json"
        if request.content_length.to_i > MAX_BODY_BYTES || request.raw_post.bytesize > MAX_BODY_BYTES
          return render_error("request_too_large", :content_too_large)
        end
        body = JSON.parse(request.raw_post)
        unless body.is_a?(Hash) && (body.keys - FIELDS).empty?
          return render_error("invalid_account", :unprocessable_content)
        end
        account = ChurchNext::Linker.new.submit!(external_user_id: body["church_next_user_id"],
          first_name: body["first_name"], last_name: body["last_name"], email: body["email"],
          email_verified: body["email_verified"], photo_available: body.fetch("photo_available", false))
        render json: {church_next_user_id: account.external_user_id, linked: account.linked?,
                      status: account.status}, status: account.linked? ? :ok : :accepted
      rescue ChurchNext::Linker::Invalid, JSON::ParserError
        render_error("invalid_account", :unprocessable_content)
      rescue ChurchNext::Linker::NotReady
        render_error("directory_not_ready", :service_unavailable)
      end

      private

      def authenticate_integration
        expected = ENV["CHURCHNEXT_API_TOKEN"]
        unless expected.is_a?(String) && expected.match?(/\A[\x21-\x7E]{32,1024}\z/)
          return render_error("integration_not_configured", :service_unavailable)
        end

        scheme, provided = request.authorization.to_s.split(" ", 2)
        allowed = scheme == "Bearer" && provided.present? && provided.bytesize <= 1024 &&
          ActiveSupport::SecurityUtils.secure_compare(Digest::SHA256.digest(provided),
            Digest::SHA256.digest(expected))
        render_error("unauthorized", :unauthorized) unless allowed
      end

      def private_response
        response.headers["Cache-Control"] = "private, no-store"
      end

      def render_error(code, status)
        render json: {error: code}, status: status
      end
    end
  end
end
