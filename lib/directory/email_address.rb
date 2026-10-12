require "uri"

module Directory
  module EmailAddress
    def self.normalize(value)
      return nil unless value.is_a?(String)

      normalized = value.strip.downcase
      normalized if normalized.bytesize <= 254 && normalized.match?(URI::MailTo::EMAIL_REGEXP)
    end
  end
end
