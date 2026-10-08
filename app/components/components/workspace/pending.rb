module Components
  module Workspace
    class Pending < Page
      def initialize(view:)
        @view = view
      end

      def view_template
        title = (@view == :map) ? "Where people live" : "Notice what is changing"
        page(title, active: @view) do
          h1(class: "text-4xl font-semibold tracking-tight") { title }
          div(class: "#{CARD} mt-8 max-w-2xl p-8") do
            icon((@view == :map) ? "map" : "history")
            h2(class: "mt-4 text-xl font-semibold") do
              plain (@view == :map) ? "Private map setup" : "Change history setup"
            end
            p(class: "mt-3 leading-relaxed text-stone-500") do
              if @view == :map
                plain "The people directory and town filters are ready. Pins and heatmaps need"
                plain " the selected private OpenStreetMap tiles and geocoding service."
              else
                plain "This directory shows the current observed person data. Scheduled comparisons"
                plain " will add a factual change feed and discovery-time windows"
                plain " in the history phase."
              end
            end
            a(href: view_context.dashboard_path, class: "#{BUTTON} mt-6") do
              plain "Return to your people"
            end
          end
        end
      end
    end
  end
end
