module Directory
  class ChangesQuery
    PAGE_SIZE = 24
    SECTIONS = {
      connection: ["connection_status_changed", "Connection status", "connection_page"],
      household: ["family_composition_changed", "Household membership", "household_page"],
      address: ["home_address_changed", "Address changed", "address_page"]
    }.freeze
    Section = Struct.new(:key, :param, :title, :events, :page, :total)

    attr_reader :days, :errors, :filters, :options, :policy, :sections, :total

    def initialize(actor:, filters: {}, pages: {})
      values = filters.to_h.stringify_keys
      @days = values["change_days"].presence || "30"
      people = Query.new(actor: actor, filters: values.except("change_days"))
      @filters, @options, @policy = people.filters.merge("change_days" => @days.to_s), people.options, people.policy
      @errors = people.errors.dup
      @errors << "Record agreed data decisions before viewing change history." unless people.confirmed?
      @errors << "History permission is required." unless actor.view_history?
      unless PersonChangeEvent::WINDOWS.map(&:to_s).include?(@days.to_s)
        @errors << "Choose a discovery window of 7, 14, 30, or 90 days."
      end
      scope = PersonChangeEvent.visible_to(actor, policy: policy)
        .where(person_profile_id: people.filtered_scope.select(:id))
      scope = errors.any? ? scope.none : scope.where(discovered_at: @days.to_i.days.ago..Time.current)
      @sections = SECTIONS.map do |key, (type, title, page_param)|
        section_scope = scope.where(event_type: type)
        page = pages.to_h[page_param].to_s.to_i.clamp(1, 10000)
        Section.new(key, page_param, title,
          section_scope.includes(:person_profile, :campus)
            .order(discovered_at: :desc, id: :desc)
            .limit(PAGE_SIZE).offset((page - 1) * PAGE_SIZE).to_a,
          page, section_scope.count)
      end
      @total = sections.sum(&:total)
    end
  end
end
