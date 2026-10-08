module Directory
  class PersonView
    attr_reader :person

    def initialize(person:, actor:, policy: DataPolicy.current)
      @person = person
      @actor = actor
      @policy = policy
    end

    def address
      return {} unless @policy.selected_fields.include?("home_address")
      values = {"status" => person.home_status, "city" => person.city,
                "state" => person.state, "country" => person.country}
      if @actor.can_access?(person.campus_id, :locations)
        values.merge!(person.private_address)
      end
      values
    end

    def attributes
      person.custom_attributes.slice(*@policy.attribute_keys)
    end

    def household_members
      return [] unless @policy.selected_fields.include?("household")
      scope = @actor.campuses.active.pluck(:rock_id)
      Array(person.household["members"]).select do |member|
        scope.include?(member["campus_rock_id"])
      end
    end

    def photo?
      @policy.selected_fields.include?("photo") && person.photo_id.present? &&
        @actor.can_access?(person.campus_id, :photos)
    end
  end
end
