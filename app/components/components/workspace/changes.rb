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
          if @query.events.empty?
            div(class: "#{CARD} p-8") do
              h2(class: "text-xl font-semibold") { "No changes discovered in this view" }
              p(class: "mt-3 text-stone-500") do
                plain "The first successful import establishes a quiet baseline."
                plain " Later completed imports report observed differences here."
              end
            end
          else
            ul(class: "#{CARD} divide-y divide-stone-100") do
              @query.events.each do |event|
                view = Directory::ChangeView.new(event: event, actor: @actor)
                li(class: "p-6") do
                  a(href: view_context.workspace_person_path(event.person_profile),
                    class: "font-semibold text-teal-800 underline") { event.person_profile.display_name }
                  h2(class: "mt-2 font-semibold") { view.title }
                  p(class: "mt-2 text-sm text-stone-600") { view.description }
                  p(class: "mt-3 text-xs text-stone-500") do
                    plain "Discovered #{event.discovered_at.in_time_zone.strftime("%b %-d, %Y %H:%M %Z")}. "
                    plain "#{event.campus.name}."
                  end
                end
              end
            end
          end
          div(class: "mt-6 flex gap-5 text-sm") do
            if @query.page > 1
              a(href: view_context.workspace_changes_path(page: @query.page - 1)) { "Previous" }
            end
            if @query.page * Directory::ChangesQuery::PAGE_SIZE < @query.total
              a(href: view_context.workspace_changes_path(page: @query.page + 1)) { "Next" }
            end
          end
        end
      end

      private

      def field(label, key, type)
        label do
          plain label
          input(name: "filters[#{key}]", type: type, value: @query.filters[key], class: INPUT)
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
