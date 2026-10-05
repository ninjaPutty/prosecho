module Components
  module Admin
    class CampusForm < Page
      def initialize(campus:, parents:)
        @campus = campus
        @parents = parents
      end

      def view_template
        page("Edit campus") do
          errors_for(@campus)
          action = view_context.admin_campus_path(@campus)
          div(class: "max-w-xl rounded-xl bg-white p-6 shadow-sm") do
            post_form(action: action, method: "patch") do
              field(label: "Campus name", name: "campus[name]", value: @campus.name, required: true)
              p(class: "text-sm text-stone-600") { "Rock campus ID: #{@campus.rock_id}" }
              label(for: "parent", class: "block font-medium") { "Parent campus (optional)" }
              select(id: "parent", name: "campus[parent_id]", class: INPUT) do
                option(value: "") { "None" }
                @parents.each do |parent|
                  option(value: parent.id, selected: @campus.parent_id == parent.id) { parent.name }
                end
              end
              toggle(label: "Active campus", name: "campus[active]", checked: @campus.active?)
              p(class: "text-sm text-stone-600") do
                plain "This is the local organization and Rock ID mapping. It does not change Rock."
                plain " Fetching from Rock refreshes the campus name and active status."
              end
              button(type: "submit", class: BUTTON) { "Save campus" }
              a(href: view_context.admin_root_path, class: "ml-4 underline") { "Cancel" }
            end
          end
        end
      end
    end
  end
end
