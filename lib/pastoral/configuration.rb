require "uri"
require "yaml"

module Pastoral
  class Configuration
    ROCK_HOST = "https://rock.chapel.org"

    def self.load(environment: ENV)
      new(YAML.safe_load_file(Rails.root.join("config/pastoral.yml")), environment,
        policy: DataPolicy.current)
    end

    def initialize(decisions, environment, policy: DataPolicy.current)
      @decisions = decisions
      @environment = environment
      @policy = policy
    end

    def blockers
      (directory_blockers + map_blockers + ["Live sync is not implemented in Phase 0"]).uniq
    end

    def data_blockers
      result = []
      result << "Data decisions have not been approved" unless approved?("data")
      DataPolicy::RETENTION_FIELDS.each do |field|
        value = @policy.public_send(field)
        unless value.is_a?(Integer) && value.positive?
          result << "#{field.to_s.humanize} must be a positive number of days"
        end
      end
      DataPolicy::TEXT_FIELDS.each do |field|
        result << "Data decision #{field} is missing" if @policy.public_send(field).blank?
      end
      unless (DataPolicy::MINIMUM_FIELDS - Array(@policy.selected_fields)).empty?
        result << "Initial fields must include first name, last name, and primary campus"
      end
      result
    end

    def data_decisions
      @policy.decisions
    end

    def directory_blockers
      result = data_blockers
      result << "Rock runtime key is missing" if rock_api_key.blank?
      result << "Rock host must be #{ROCK_HOST}" unless rock_base_url == ROCK_HOST
      result
    end

    def directory_ready?
      directory_blockers.empty?
    end

    def map_blockers
      result = directory_blockers
      result << "Private map providers have not been approved" unless approved?("maps")
      if public_map_provider?
        result << "Map providers must not use public OSM services"
      end
      unless configured_map_provider?("PASTORAL_GEOCODER_URL", "geocoder_host") &&
          configured_map_provider?("PASTORAL_TILE_URL", "tile_host")
        result << "Private map endpoints must match the approved hosts"
      end
      unless Array(@policy.selected_fields).include?("home_address")
        result << "Home address must be included in the field allowlist for the map"
      end
      result
    end

    def map_ready?
      map_blockers.empty?
    end

    def inspect
      "#<#{self.class.name} read_only=true live_sync_enabled=false>"
    end

    def live_sync_enabled?
      false
    end

    def read_only?
      true
    end

    def ready?
      blockers.empty?
    end

    def rock_api_key
      @environment["ROCK_API_KEY"]
    end

    def rock_base_url
      @environment.fetch("ROCK_BASE_URL", ROCK_HOST)
    end

    private

    def approved?(section)
      if section == "data"
        return @policy.persisted? && @policy.confirmed? && @policy.valid?
      end
      decision = @decisions.fetch(section)
      decision["approved_by"].present? && decision["approved_at"].present?
    end

    def configured_map_provider?(key, host_key)
      url = @environment[key]
      approved_host = @decisions.dig("maps", host_key)
      return false if url.blank? || approved_host.blank?

      uri = URI.parse(url.gsub(/\{[^}]+\}/, "0"))
      uri.scheme == "https" && uri.host == approved_host && uri.userinfo.nil? && uri.port == 443
    rescue URI::InvalidURIError
      false
    end

    def public_map_provider?
      %w[PASTORAL_GEOCODER_URL PASTORAL_TILE_URL].any? do |key|
        value = @environment[key]
        next false if value.blank?

        host = URI.parse(value.gsub(/\{[^}]+\}/, "0")).host
        host.nil? || host == "openstreetmap.org" || host.end_with?(".openstreetmap.org")
      rescue URI::InvalidURIError
        true
      end
    end
  end
end
