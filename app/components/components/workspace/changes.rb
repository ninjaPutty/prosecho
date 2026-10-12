module Components
  module Workspace
    class Changes < Page
      def initialize(query:, actor:)
        @query, @actor = query, actor
      end

      def view_template
        page("Recently discovered changes", active: :changes) do
          h1(class: "text-4xl font-semibold tracking-tight") { "Recently discovered changes" }
          p(class: "mt-3 text-stone-500") do
            plain "Observed differences in Rock data. Discovery time is not the exact time a change occurred."
          end
          post_form(action: view_context.workspace_filters_path) do
            input(type: "hidden", name: "view", value: "changes")
            div(class: "my-6 grid gap-4 rounded-2xl bg-white p-5 sm:grid-cols-3") do
              select_filter("Campus", "campus_id", @query.options[:campuses].map { |c| [c.id, c.name] })
              select_filter("Connection status", "connection_status",
                @query.options[:statuses].map { |id, name| [id || "unknown", name || "Unknown"] })
              select_filter("Home town", "town", @query.options[:towns].map { |town| [town, town] })
              field("Name", "search", "search")
              field("Minimum age", "min_age", "number")
              field("Maximum age", "max_age", "number")
              label do
                plain "Discovered within"
                select(name: "filters[change_days]", class: INPUT) do
                  {7 => "1 week", 14 => "2 weeks", 30 => "30 days", 90 => "90 days"}.each do |days, text|
                    option(value: days, selected: @query.days.to_s == days.to_s) { text }
                  end
                end
              end
              button(type: "submit", class: BUTTON) { "Apply filters" }
            end
          end
          post_form(action: view_context.workspace_filters_path, method: "delete") do
            input(type: "hidden", name: "view", value: "changes")
            button(type: "submit", class: "mb-6 text-sm underline") { "Clear filters" }
          end
          if @query.errors.any?
            div(role: "alert", class: "mb-6 rounded-xl bg-red-50 p-4 text-red-800") do
              @query.errors.each { |error| p { error } }
            end
          end
          p(class: "mb-4 text-sm text-stone-500") { "#{@query.total} discovered changes in this view" }
          @query.sections.each { |section| render_section(section) }
        end
      end

      private

      def field(label, key, type)
        label do
          plain label
          input(name: "filters[#{key}]", type: type, value: @query.filters[key], class: INPUT)
        end
      end

      def render_section(section)
        section(class: "mb-8") do
          div(class: "mb-3 flex items-baseline justify-between gap-4") do
            h2(class: "text-2xl font-semibold tracking-tight") { section.title }
            p(class: "text-sm text-stone-500") { "#{section.total} changes" }
          end
          if section.events.empty?
            div(class: "#{CARD} p-5 text-sm text-stone-500") { "No changes in this section." }
          else
            ul(class: "#{CARD} w-full divide-y divide-stone-100") do
              section.events.each { |event| render_event(event) }
            end
          end
          render_pagination(section)
        end
      end

      def render_event(event)
        person = event.person_profile
        person_view = Directory::PersonView.new(person: person, actor: @actor)
        change_view = Directory::ChangeView.new(event: event, actor: @actor)
        li(class: "w-full p-4 sm:p-5") do
          div(class: "grid w-full gap-4 sm:grid-cols-[minmax(0,1fr)_minmax(0,2fr)] " \
            "lg:grid-cols-[minmax(13rem,1fr)_minmax(0,2fr)_12rem] lg:items-start") do
            a(href: view_context.workspace_person_path(person),
              class: "flex min-w-0 items-center gap-3 font-semibold text-teal-800 underline") do
              portrait(person_view, size: "size-12")
              span(class: "min-w-0 truncate") { person.display_name }
            end
            div(class: "min-w-0") do
              h3(class: "font-semibold text-stone-900") { change_view.title }
              p(class: "mt-1 text-sm text-stone-600") { change_view.description }
            end
            div(class: "text-xs text-stone-500 lg:text-right") do
              p(class: "font-medium text-stone-700") do
                plain event.discovered_at.in_time_zone.strftime("%b %-d, %Y %H:%M %Z")
              end
              p(class: "mt-1") { event.campus.name }
            end
          end
        end
      end

      def render_pagination(section)
        return if section.total <= Directory::ChangesQuery::PAGE_SIZE

        params = @query.sections.each_with_object({}) do |item, values|
          value = view_context.params[item.param]
          values[item.param] = value if value.present?
        end
        div(class: "mt-3 flex justify-end gap-5 text-sm") do
          if section.page > 1
            a(href: view_context.workspace_changes_path(params.merge(section.param => section.page - 1))) do
              "Previous #{section.title.downcase}"
            end
          end
          if section.page * Directory::ChangesQuery::PAGE_SIZE < section.total
            a(href: view_context.workspace_changes_path(params.merge(section.param => section.page + 1))) do
              "Next #{section.title.downcase}"
            end
          end
        end
      end

      def select_filter(label, key, choices)
        label do
          plain label
          select(name: "filters[#{key}]", class: INPUT) do
            option(value: "") { "All" }
            choices.each do |value, text|
              option(value: value, selected: @query.filters[key] == value.to_s) { text }
            end
          end
        end
      end
    end
  end
end
