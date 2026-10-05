module Components
  module Admin
    class AccountForm < Page
      def initialize(user:, campuses:, new_record: false)
        @user = user
        @campuses = campuses
        @new_record = new_record
      end

      def view_template
        page(@new_record ? "Create account" : "Edit account") do
          errors_for(@user)
          action = if @new_record
            view_context.admin_accounts_path
          else
            view_context.admin_account_path(@user)
          end
          div(class: "max-w-2xl rounded-xl bg-white p-6 shadow-sm") do
            post_form(action: action, method: @new_record ? "post" : "patch") do
              field(label: "Email", name: "user[email]", value: @user.email,
                type: "email", required: true)
              field(label: @new_record ? "Password" : "New password (leave blank to keep current)",
                name: "user[password]", type: "password", required: @new_record)
              field(label: "Confirm new password", name: "user[password_confirmation]",
                type: "password", required: @new_record)
              label(for: "role", class: "block font-medium") { "Account role" }
              select(id: "role", name: "user[role]", class: INPUT) do
                %w[staff administrator].each do |role|
                  option(value: role, selected: @user.role == role) { role.humanize }
                end
              end
              toggle(label: "Active account", name: "user[active]", checked: @user.active?)
              fieldset(class: "space-y-3") do
                legend(class: "mb-3 font-semibold") { "Pastoral permissions" }
                p(class: "text-sm text-stone-600") do
                  plain "These permissions apply only to assigned campuses."
                end
                toggle(label: "View profile photos", name: "user[view_photos]",
                  checked: @user.view_photos?)
                toggle(label: "View change history", name: "user[view_history]",
                  checked: @user.view_history?)
                toggle(label: "View precise locations", name: "user[view_locations]",
                  checked: @user.view_locations?)
              end
              fieldset(class: "space-y-3") do
                legend(class: "mb-3 font-semibold") { "Campus access" }
                input(type: "hidden", name: "user[campus_ids][]", value: "")
                assigned = @user.campus_ids
                @campuses.each do |campus|
                  label(class: "flex items-center gap-3") do
                    input(type: "checkbox", name: "user[campus_ids][]", value: campus.id,
                      checked: assigned.include?(campus.id))
                    plain campus.name
                    plain " (inactive)" unless campus.active?
                  end
                end
                if @campuses.empty?
                  p { "No campuses yet. Fetch campuses from Rock on the administration dashboard." }
                end
              end
              button(type: "submit", class: BUTTON) { "Save account" }
              a(href: view_context.admin_root_path, class: "ml-4 underline") { "Cancel" }
            end
          end
        end
      end
    end
  end
end
