module Components
  module Workspace
    class Person < Page
      def initialize(person_view:, frame: false)
        @view = person_view
        @person = person_view.person
        @frame = frame
      end

      def view_template
        if @frame
          details
        else
          page(@person.display_name) { details }
        end
      end

      private

      def details
        turbo_frame(id: "person_details") do
          div(class: "p-6") do
            portrait(@view, size: "size-20")
            h2(class: "mt-4 text-2xl font-semibold") { @person.display_name }
            p(class: "mt-2 text-sm text-stone-500") { @person.campus.name }
            dl(class: "mt-6 space-y-5 text-sm") do
              detail("Connection", @person.connection_status_label || "Unknown")
              detail("Age", @person.age ? "#{@person.age} years" : "Unknown")
              address = @view.address
              parts = [address["street1"], address["street2"], address["city"], address["state"],
                address["postal_code"], address["country"]].compact.reject(&:blank?)
              detail("Home", parts.any? ? parts.join(", ") : @person.home_status.humanize)
              detail("Marital status", @person.marital_status_label || "Unknown")
              members = @view.household_members
              detail("Household", "#{members.size} members in your authorized campus scope")
            end
            unless @view.attributes.empty?
              h3(class: "mt-6 font-semibold") { "Approved attributes" }
              @view.attributes.each do |key, value|
                p(class: "mt-2 text-sm text-stone-500") { "#{key}: #{value.presence || "Unknown"}" }
              end
            end
            p(class: "mt-6 text-xs text-stone-400") do
              plain "Observed #{@person.observed_at.in_time_zone.strftime("%b %-d, %Y %H:%M %Z")}."
            end
            a(href: "https://rock.chapel.org/person/#{@person.rock_id}", target: "_blank",
              rel: "noopener noreferrer",
              class: "mt-5 inline-flex items-center gap-2 text-sm text-teal-800") do
              plain "Open in Rock"
              icon("external-link")
            end
            a(href: view_context.dashboard_path, data_turbo_frame: "_top",
              class: "mt-5 block text-sm text-stone-500 underline") { "Back to people" }
          end
        end
      end

      def detail(label, value)
        div do
          dt(class: "text-xs font-semibold uppercase tracking-wide text-stone-400") { label }
          dd(class: "mt-1 leading-relaxed") { value }
        end
      end
    end
  end
end
