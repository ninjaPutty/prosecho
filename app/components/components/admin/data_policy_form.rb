module Components
  module Admin
    class DataPolicyForm < Page
      def initialize(policy:)
        @policy = policy
      end

      def view_template
        page("Data decisions") do
          p(class: "mb-6 text-stone-600") do
            plain "Record retention periods and the initial Rock data contract."
            plain " You can save a draft while deciding."
            plain " This page does not import or delete people."
          end
          if @policy.persisted?
            p(class: "mb-6 text-sm text-stone-600") do
              plain "#{@policy.status.humanize}. Last saved by #{@policy.recorded_by.email} "
              plain "at #{@policy.updated_at.in_time_zone.strftime("%Y-%m-%d %H:%M %Z")}."
            end
          else
            p(class: "mb-6 text-sm text-stone-600") do
              plain "No decisions saved yet."
              plain " Source descriptions below are suggested from Rock discovery."
            end
          end
          errors_for(@policy)
          post_form(action: view_context.admin_data_policy_path, method: "patch") do
            input(type: "hidden", name: "data_policy[revision]", value: @policy.revision)
            section(class: "rounded-xl bg-white p-6 shadow-sm") do
              h2(class: "mb-4 text-xl font-semibold") { "Retention" }
              p(class: "mb-5 text-sm text-stone-600") do
                plain "Enter positive whole days. These decisions will guide future cleanup jobs"
                plain " and backup configuration; saving them does not run cleanup."
              end
              div(class: "grid gap-5 sm:grid-cols-2") do
                {
                  profile_retention_days: "Profiles after leaving the synchronized population",
                  history_retention_days: "Change history (previous addresses and households)",
                  log_retention_days: "Access and audit logs",
                  backup_retention_days: "Backups containing retained data"
                }.each do |key, label|
                  field(label: "#{label} (days)", name: "data_policy[#{key}]",
                    value: @policy.public_send(key), type: "number")
                end
              end
              text_area(label: "Retention notes or exceptions", key: :retention_notes)
            end
            section(class: "rounded-xl bg-white p-6 shadow-sm") do
              h2(class: "mb-4 text-xl font-semibold") { "Address and household interpretation" }
              text_area(label: "Primary home-address source", key: :address_source)
              text_area(label: "Missing or ambiguous home-address handling", key: :address_handling)
              text_area(label: "Household membership and roles source", key: :household_source)
              text_area(label: "How household membership changes should be interpreted",
                key: :household_handling)
              text_area(label: "Meaning of Rock's FamilyStatus attribute",
                key: :family_status_meaning)
              p(class: "mt-4 text-sm text-stone-600") do
                plain "Describe sources and rules, not individual people. The observed FamilyStatus"
                plain " values describe engagement, not marriage or divorce."
              end
            end
            section(class: "rounded-xl bg-white p-6 shadow-sm") do
              h2(class: "mb-4 text-xl font-semibold") { "Initial person field allowlist" }
              p(class: "mb-5 text-sm text-stone-600") do
                plain "Choose the fields the first person import may read. First name, last name,"
                plain " and primary campus are required for identification and access scope."
                plain " Rock identity keys and sync timestamps are system metadata."
              end
              input(type: "hidden", name: "data_policy[selected_fields][]", value: "")
              div(class: "grid gap-3 sm:grid-cols-2") do
                DataPolicy::FIELD_LABELS.each do |key, label|
                  label(class: "flex items-center gap-3") do
                    input(type: "checkbox", name: "data_policy[selected_fields][]", value: key,
                      checked: Array(@policy.selected_fields).include?(key))
                    plain label
                  end
                end
              end
              text_area(label: "Optional custom Rock attribute keys (one per line)",
                key: :attribute_keys_text)
              p(class: "mt-4 text-sm text-stone-600") do
                plain "Leave custom keys blank to import no custom attributes. Nothing is selected"
                plain " automatically from HR, health, giving, or other attribute categories."
              end
            end
            section(class: "rounded-xl bg-white p-6 shadow-sm") do
              label(for: "policy_status", class: "block font-semibold") { "Decision status" }
              select(id: "policy_status", name: "data_policy[status]", class: INPUT) do
                option(value: "draft", selected: !@policy.confirmed?) { "Save as draft" }
                option(value: "confirmed", selected: @policy.confirmed?) do
                  plain "Record agreed decisions"
                end
              end
              p(class: "my-4 text-sm text-stone-600") do
                plain "Agreed decisions require all retention periods and source/handling rules."
                plain " The administrator and confirmation time are recorded on the server."
              end
              button(type: "submit", class: BUTTON) { "Save decisions" }
              a(href: view_context.admin_root_path, class: "ml-4 underline") do
                plain "Back to administration"
              end
            end
          end
        end
      end

      private

      def text_area(label:, key:)
        id = "data_policy_#{key}"
        div(class: "mt-5") do
          label(for: id, class: "block font-medium") { label }
          textarea(id: id, name: "data_policy[#{key}]", rows: 3, class: INPUT) do
            plain @policy.public_send(key).to_s
          end
        end
      end
    end
  end
end
