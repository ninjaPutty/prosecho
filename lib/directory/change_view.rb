module Directory
  class ChangeView
    def initialize(event:, actor:)
      @event, @actor = event, actor
    end

    def description
      case @event.event_type
      when "connection_status_changed"
        "#{status(@event.previous_value)} -> #{status(@event.current_value)}"
      when "home_address_changed"
        "#{address(@event.previous_value)} -> #{address(@event.current_value)}"
      when "family_composition_changed"
        campuses = @actor.campuses.active.pluck(:rock_id)
        additions = Array(@event.details["added"]).count { |m| campuses.include?(m["campus_rock_id"]) }
        roles = Array(@event.details["roles"]).count { |m| campuses.include?(m["campus_rock_id"]) }
        removed = Array(@event.details["removed"]).count { |m| campuses.include?(m["campus_rock_id"]) }
        parts = []
        parts << "Primary household reference changed" if @event.household_reference_changed?
        parts << "#{additions} newly observed members" if additions.positive?
        parts << "#{roles} member role changes" if roles.positive?
        parts << "#{removed} members no longer in the complete roster" if removed.positive?
        parts.join(". ")
      end
    end

    def title
      case @event.event_type
      when "connection_status_changed" then "Connection status changed"
      when "home_address_changed"
        if [@event.previous_value, @event.current_value].all? { |v| v["status"] == "known" }
          "Home address updated"
        else
          "Home address availability changed"
        end
      when "family_composition_changed" then "Household membership observed"
      end
    end

    private

    def address(value)
      return value["status"].to_s.humanize.presence || "Unknown" unless value["status"] == "known"
      keys = @actor.view_locations? ? %w[street1 street2 city state postal_code country] : %w[city state country]
      value.values_at(*keys).compact.reject(&:blank?).join(", ").presence || "Details unavailable"
    end

    def status(value)
      value["label"].presence || "Unknown"
    end
  end
end
