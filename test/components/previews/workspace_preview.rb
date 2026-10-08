class WorkspacePreview < Lookbook::Preview
  class PreviewActor
    def administrator?
      false
    end

    def can_access?(*args)
      false
    end
  end

  def changes_setup
    render Components::Workspace::Pending.new(view: :changes)
  end

  def empty_people
    render Components::Workspace::People.new(query: sample_query([]), actor: PreviewActor.new)
  end

  def failed_refresh
    run = PersonRefreshRun.new(status: "failed", page_count: 4,
      error_code: "invalid_person_identity", checkpoint_retained: true,
      error_details: {"phase" => "read", "page" => 5, "rock_id" => 501, "fields" => ["Guid"]})
    run.define_singleton_method(:checkpoint_authorized?) { true }
    run.define_singleton_method(:entries) { [] }
    render Components::Workspace::People.new(query: sample_query([]), actor: PreviewActor.new, run: run)
  end

  def map_setup
    render Components::Workspace::Pending.new(view: :map)
  end

  def populated_people
    campus = Campus.new(id: "00000000-0000-4000-8000-000000000001", name: "Example campus", rock_id: 1)
    people = %w[Alex Casey Morgan].each_with_index.map do |name, index|
      person = PersonProfile.new(id: "00000000-0000-4000-8000-#{(index + 101).to_s.rjust(12, "0")}",
        first_name: name, last_name: "Example", display_name: "#{name} Example",
        birth_date: Date.new(1990 + index, 5, 10), city: "Example Town",
        connection_status_label: "Connected", observed_at: Time.utc(2026, 1, 1))
      person.campus = campus
      person
    end
    render Components::Workspace::People.new(query: sample_query(people), actor: PreviewActor.new)
  end

  private

  def sample_query(people)
    query = Struct.new(:people, :total, :filters, :options, :policy, :errors, :page,
      :last_observed_at).new(people: people, total: people.size, filters: {},
        options: {campuses: [], statuses: [], towns: []}, policy: DataPolicy.new(DataPolicy.default_attributes),
        errors: [], page: 1, last_observed_at: nil)
    query.define_singleton_method(:confirmed?) { true }
    query
  end
end
