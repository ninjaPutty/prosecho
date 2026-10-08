module Components
  module Admin
    class Dashboard < Page
      def initialize(accounts:, campuses:, page: 1, policy: nil, refresh_run: nil)
        @accounts = accounts
        @campuses = campuses
        @page = page
        @policy = policy
        @refresh_run = refresh_run
      end

      def view_template
        page("Account administration") do
          p(class: "mb-8 text-stone-600") do
            plain "Manage staff access and the local campus structure."
            plain " These changes do not edit Rock."
          end
          section(class: "mb-10 rounded-xl bg-white p-6 shadow-sm") do
            h2(class: "mb-3 text-xl font-semibold") { "Rock people refresh" }
            p(class: "mb-5 text-stone-600") do
              plain "Import people from every campus in the catalog, including inactive campuses."
              plain " Viewing grants and directory filters do not limit this administrator operation."
            end
            if @policy&.confirmed?
              post_form(action: view_context.workspace_refresh_path) do
                if @refresh_run&.resumable?
                  input(type: "hidden", name: "resume_run_id", value: @refresh_run.id)
                end
                label = if @refresh_run&.resumable?
                  "Retry from saved checkpoint"
                elsif @refresh_run&.active?
                  "Resume/check refresh"
                else
                  "Refresh people from Rock"
                end
                button(type: "submit", class: BUTTON) { label }
              end
            else
              p { "Record agreed data decisions before refreshing people." }
            end
            if @refresh_run
              p(class: "mt-4 text-sm text-stone-600") do
                plain "Latest refresh: #{@refresh_run.status.humanize}. "
                plain "#{@refresh_run.page_count} pages; #{@refresh_run.imported_count} people published."
              end
              p(class: "mt-2 text-sm text-red-800") { @refresh_run.error_message } if @refresh_run.error_code
            end
          end
          section(class: "mb-10 rounded-xl bg-white p-6 shadow-sm") do
            div(class: "mb-6 flex flex-wrap items-center justify-between gap-4") do
              h2(class: "text-xl font-semibold") { "Accounts" }
              a(href: view_context.new_admin_account_path, class: BUTTON) { "Create account" }
            end
            ul(class: "divide-y divide-stone-100") do
              @accounts.each do |user|
                li(class: "flex flex-wrap items-center justify-between gap-4 py-4") do
                  div do
                    p(class: "font-semibold") { user.email }
                    p(class: "text-sm text-stone-600") do
                      plain "#{user.role.humanize} / #{user.active? ? "Active" : "Disabled"}"
                    end
                    p(class: "text-sm text-stone-600") do
                      plain user.campuses.map(&:name).join(", ").presence || "No campus access"
                    end
                  end
                  a(href: view_context.edit_admin_account_path(user),
                    class: "text-teal-800 underline") do
                    plain "Edit account"
                  end
                end
              end
            end
            div(class: "mt-4 flex gap-5") do
              if @page > 1
                a(href: view_context.admin_root_path(page: @page - 1)) { "Previous accounts" }
              end
              if @accounts.size == 30
                a(href: view_context.admin_root_path(page: @page + 1)) { "Next accounts" }
              end
            end
          end
          section(class: "rounded-xl bg-white p-6 shadow-sm") do
            div(class: "mb-6 flex flex-wrap items-center justify-between gap-4") do
              h2(class: "text-xl font-semibold") { "Campus structure" }
              post_form(action: view_context.import_admin_campuses_path) do
                button(type: "submit", class: BUTTON) { "Fetch campuses from Rock" }
              end
            end
            p(class: "mb-4 text-sm text-stone-600") do
              plain "Parent campuses organize the structure; they do not grant inherited access."
              plain " Fetching refreshes names and active status."
              plain " Local parents and staff grants are preserved."
            end
            if @campuses.empty?
              p { "Fetch your campuses from Rock to start assigning staff access." }
            end
            ul(class: "divide-y divide-stone-100") do
              @campuses.each do |campus|
                li(class: "flex flex-wrap items-center justify-between gap-4 py-4") do
                  div do
                    p(class: "font-semibold") { campus.name }
                    p(class: "text-sm text-stone-600") do
                      plain "Rock ID #{campus.rock_id} / #{campus.active? ? "Active" : "Inactive"}"
                      plain " / Parent: #{campus.parent.name}" if campus.parent
                    end
                  end
                  a(href: view_context.edit_admin_campus_path(campus),
                    class: "text-teal-800 underline") do
                    plain "Edit campus"
                  end
                end
              end
            end
          end
          section(class: "mt-10 rounded-xl bg-white p-6 shadow-sm") do
            h2(class: "mb-3 text-xl font-semibold") { "Retention and data contract" }
            p(class: "mb-5 text-stone-600") do
              plain "Record retention periods, address and household rules,"
              plain " and the initial field allowlist."
            end
            a(href: view_context.admin_data_policy_path, class: BUTTON) { "Data decisions" }
          end
        end
      end
    end
  end
end
