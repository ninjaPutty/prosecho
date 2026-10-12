class ChangesPreview < Lookbook::Preview
  class HistoryActor
    def administrator?
      false
    end

    def view_locations?
      false
    end
  end

  def empty
    render Components::Workspace::Changes.new(query: query([]), actor: HistoryActor.new)
  end

  def populated
    campus = Campus.new(id: "00000000-0000-4000-8000-000000000001", name: "Example campus", rock_id: 1)
    person = PersonProfile.new(id: "00000000-0000-4000-8000-000000000101", display_name: "Alex Example")
    event = PersonChangeEvent.new(event_type: "connection_status_changed",
      previous_value: {"label" => "Previously observed"}, current_value: {"label" => "Currently observed"},
      discovered_at: Time.utc(2026, 10, 8, 12))
    event.person_profile = person
    event.campus = campus
    render Components::Workspace::Changes.new(query: query([event]), actor: HistoryActor.new)
  end

  private

  def query(events)
    sections = Directory::ChangesQuery::SECTIONS.map do |key, (type, title, param)|
      section_events = events.select { |event| event.event_type == type }
      Directory::ChangesQuery::Section.new(key, param, title, section_events, 1, section_events.size)
    end
    Struct.new(:days, :errors, :filters, :options, :sections, :total).new(
      days: 30, errors: [], filters: {}, options: {campuses: [], statuses: [], towns: []},
      sections: sections, total: events.size
    )
  end
end
