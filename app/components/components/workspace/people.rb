module Components
  module Workspace
    class People < Page
      GRID = "grid gap-6 lg:grid-cols-[240px_minmax(0,1fr)] " \
        "xl:grid-cols-[240px_minmax(0,1fr)_320px]"
      def initialize(query:, actor:, run: nil)
        @query = query
        @actor = actor
        @run = run
      end

      def view_template
        page("People at a glance") do
          div(class: "mb-8 flex flex-wrap items-end justify-between gap-5") do
            div do
              p(class: "mb-2 text-sm font-medium text-teal-800") do
                plain "Know the people. Notice the story."
              end
              h1(class: "text-4xl font-semibold tracking-tight") { "People at a glance" }
              p(class: "mt-3 text-stone-500") do
                plain "A familiar face, a clearer picture, a thoughtful next step."
              end
            end
            if @query.confirmed?
              post_form(action: view_context.workspace_refresh_path) do
                if @run&.resumable?
                  input(type: "hidden", name: "resume_run_id", value: @run.id)
                end
                button(type: "submit", class: BUTTON) do
                  icon("refresh-cw")
                  label = if @run&.resumable?
                    "Retry from saved checkpoint"
                  elsif @run&.active?
                    "Resume/check refresh"
                  else
                    "Refresh people from Rock"
                  end
                  plain label
                end
              end
            end
          end
          unless @query.confirmed?
            div(class: "#{CARD} p-8") do
              h2(class: "text-xl font-semibold") { "Data decisions are needed" }
              p(class: "mt-3 text-stone-500") do
                plain "Record complete agreed data decisions before loading or displaying people."
              end
              if @actor.administrator?
                a(href: view_context.admin_data_policy_path,
                  class: "mt-5 inline-block text-teal-800 underline") do
                  plain "Data decisions"
                end
              end
            end
            return
          end
          div(class: "mb-7 grid gap-4 sm:grid-cols-3") do
            summary("People in this view", @query.total.to_s,
              "Your campus scope and current filters")
            observed = @query.last_observed_at
            observed_label = observed ? observed.in_time_zone.strftime("%b %-d, %H:%M") : "Not yet"
            summary("Last refreshed", observed_label,
              "A local, read-only view of Rock")
            status = @run&.status || "Ready"
            hint = if @run&.status == "failed"
              "Could not finish. No partial download was published."
            else
              "Refreshes run in the background"
            end
            summary("Directory refresh", status.humanize, hint, refresh: true)
          end
          if @run&.status == "failed"
            div(role: "alert", class: "mb-6 rounded-xl bg-red-50 p-4 text-red-900") do
              p { @run.error_message }
              details = @run.diagnostic_details
              p do
                plain "Failure stage: #{details["phase"] || "unknown"}. "
                plain "Page: #{details["page"] || @run.page_count + 1}. "
                plain "Code: #{@run.error_code}."
                plain " Rock record ID: #{details["rock_id"]}." if details["rock_id"]
                plain " Fields: #{Array(details["fields"]).join(", ")}." if details["fields"]
              end
              p do
                if @run.checkpoint_retained?
                  plain "#{@run.page_count} pages and #{@run.entries.count} records retained. "
                  if @run.resumable?
                    plain "Correct the issue, then retry from the saved checkpoint."
                  else
                    plain "Access or data decisions no longer match this checkpoint; start a new refresh."
                  end
                else
                  plain "This run has no retained checkpoint; start a new refresh."
                end
              end
            end
          end
          if @run&.status&.in?(%w[queued running])
            p(role: "status", class: "mb-6 rounded-xl bg-teal-50 p-4 text-teal-900",
              data_refresh_progress: true, data_status_url: view_context.workspace_refresh_status_path) do
              span(data_refresh_message: true) do
                plain "Refresh #{@run.status}. #{@run.page_count} pages saved; #{@run.entries.count} records staged."
                plain " #{@run.duplicate_count} repeated entries merged."
                if @run.error_code == "rock_read_failed"
                  plain " #{@run.error_message}"
                  plain " Rock HTTP #{@run.error_details["http_status"]}." if @run.error_details["http_status"]
                elsif @run.error_code == "rock_not_configured"
                  plain " Waiting for the server's Rock connection configuration. Saved pages are intact."
                end
                unless Directory::WorkerHealth.online?
                  plain " No directory worker is currently online; saved work will resume when one starts."
                end
              end
              a(href: view_context.dashboard_path, class: "ml-3 underline") { "Check progress" }
            end
          end
          div(class: GRID) do
            aside(class: "#{CARD} h-fit p-5") { filters }
            section(class: "#{CARD} overflow-hidden") do
              div(class: "flex items-center justify-between border-b border-stone-100 px-6 py-5") do
                h2(class: "text-lg font-semibold") { "Your people" }
                span(class: "rounded-full bg-teal-50 px-3 py-1 text-sm text-teal-800") do
                  plain "#{@query.total} people"
                end
              end
              if @query.errors.any?
                div(role: "alert", class: "m-5 rounded-xl bg-red-50 p-4 text-red-800") do
                  @query.errors.each { |error| p { error } }
                end
              end
              if @query.people.empty?
                div(class: "px-8 py-14 text-center") do
                  div(class: "mx-auto mb-4 w-fit rounded-2xl bg-teal-50 p-4 text-teal-800") do
                    icon("users")
                  end
                  h3(class: "text-xl font-semibold") { "A little space to get started" }
                  p(class: "mx-auto mt-3 max-w-md text-stone-500") do
                    plain "Refresh your directory from Rock,"
                    plain " or widen the filters to find more people."
                  end
                end
              else
                ul(class: "divide-y divide-stone-100") do
                  @query.people.each { |person| person_row(person) }
                end
              end
              pagination
            end
            aside(class: "#{CARD} h-fit overflow-hidden lg:col-span-2 xl:col-span-1") do
              turbo_frame(id: "person_details") do
                div(class: "p-7") do
                  div(class: "mb-4 w-fit rounded-xl bg-stone-100 p-3 text-stone-500") do
                    icon("contact")
                  end
                  h2(class: "text-xl font-semibold") { "A person, not just a record" }
                  p(class: "mt-3 text-sm leading-relaxed text-stone-500") do
                    plain "Choose someone to see their campus, connection,"
                    plain " home town, and approved details."
                  end
                end
              end
            end
          end
        end
      end

      private

      def filters
        h2(class: "mb-5 font-semibold") { "Find your people" }
        post_form(action: view_context.workspace_filters_path) do
          div(class: "space-y-5") do
            label(for: "search", class: "block text-sm font-medium") do
              plain "Name"
              input(id: "search", name: "filters[search]", value: @query.filters["search"],
                class: "#{INPUT} mt-2", type: "search", placeholder: "A familiar name")
            end
            select_filter("Home campus", "campus_id",
              @query.options[:campuses].map { |campus| [campus.id, campus.name] })
            statuses = @query.options[:statuses].map do |id, name|
              [id || "unknown", name || "Unknown"]
            end
            select_filter("Connection status", "connection_status", statuses)
            div do
              p(class: "mb-2 text-sm font-medium") { "Age range" }
              div(class: "grid grid-cols-2 gap-2") do
                %w[min_age max_age].each do |key|
                  label(class: "text-xs text-stone-500") do
                    plain (key == "min_age") ? "From" : "To"
                    input(type: "number", min: 0, max: 130, name: "filters[#{key}]",
                      value: @query.filters[key], class: "#{INPUT} mt-1")
                  end
                end
              end
            end
            select_filter("Home town", "town", @query.options[:towns].map { |town| [town, town] })
            button(type: "submit", class: "#{BUTTON} w-full") { "Apply filters" }
          end
        end
        post_form(action: view_context.workspace_filters_path, method: "delete") do
          button(type: "submit", class: "mt-4 w-full text-sm text-stone-500 underline") do
            plain "Clear all filters"
          end
        end
      end

      def pagination
        return if @query.total <= Directory::Query::PAGE_SIZE
        div(class: "flex items-center justify-between border-t " \
          "border-stone-100 px-6 py-4 text-sm") do
          if @query.page > 1
            a(href: view_context.dashboard_path(page: @query.page - 1), class: "text-teal-800") do
              plain "Previous"
            end
          end
          span(class: "text-stone-500") { "Page #{@query.page}" }
          if @query.page * Directory::Query::PAGE_SIZE < @query.total
            a(href: view_context.dashboard_path(page: @query.page + 1), class: "text-teal-800") do
              plain "Next"
            end
          end
        end
      end

      def person_row(person)
        view = Directory::PersonView.new(person: person, actor: @actor, policy: @query.policy)
        li do
          a(href: view_context.workspace_person_path(person), data_turbo_frame: "person_details",
            class: "flex items-center gap-4 px-6 py-5 transition " \
              "hover:bg-teal-50/50 focus:bg-teal-50") do
            portrait(view)
            div(class: "min-w-0 flex-1") do
              p(class: "truncate font-semibold") { person.display_name }
              p(class: "mt-1 text-sm text-stone-500") do
                age = person.age ? "#{person.age} years" : "Age unknown"
                plain [person.campus.name, age, person.city].compact.join(" / ")
              end
              span(class: "mt-2 inline-block rounded-full bg-stone-100 " \
                "px-2 py-1 text-xs text-stone-600") do
                plain person.connection_status_label || "Connection unknown"
              end
            end
            span(class: "text-stone-400") { icon("chevron-right") }
          end
        end
      end

      def select_filter(label, key, options)
        label(for: key, class: "block text-sm font-medium") { label }
        select(id: key, name: "filters[#{key}]", class: "#{INPUT} mt-2") do
          option(value: "") { "All" }
          options.each do |value, name|
            option(value: value, selected: @query.filters[key] == value.to_s) { name }
          end
        end
      end

      def summary(title, value, hint, refresh: false)
        div(class: "#{CARD} p-5") do
          p(class: "text-xs font-semibold uppercase tracking-wider text-stone-500") { title }
          p(class: "mt-2 text-2xl font-semibold", data_refresh_state: refresh || nil) { value }
          p(class: "mt-2 text-xs text-stone-500") { hint }
        end
      end
    end
  end
end
