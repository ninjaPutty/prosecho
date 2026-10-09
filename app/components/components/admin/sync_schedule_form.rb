module Components
  module Admin
    class SyncScheduleForm < Page
      def initialize(schedule:)
        @schedule = schedule
      end

      def view_template
        page("Scheduled people refresh") do
          p(class: "mb-6 text-stone-600") do
            plain "Refresh all catalog campuses automatically. The default is every 24 hours."
            plain " The saved administrator authorizes imports, independently of viewing grants."
          end
          errors_for(@schedule)
          post_form(action: view_context.admin_sync_schedule_path, method: "patch") do
            input(type: "hidden", name: "sync_schedule[revision]", value: @schedule.lock_version)
            toggle(label: "Enable scheduled refreshes", name: "sync_schedule[enabled]",
              checked: @schedule.enabled?)
            field(label: "Hours between successful refreshes (1-168)",
              name: "sync_schedule[interval_hours]", value: @schedule.interval_hours, type: "number")
            button(type: "submit", class: BUTTON) { "Save schedule" }
          end
          p(class: "mt-6 text-sm text-stone-600") { "Schedule health: #{@schedule.health.humanize}." }
          if @schedule.enabled?
            p(class: "mt-3 text-sm text-stone-600") do
              plain "Next due: #{@schedule.due_at.in_time_zone.strftime("%b %-d, %Y %H:%M %Z")}."
            end
          end
          p(class: "mt-3 text-sm text-stone-600") do
            checked = @schedule.last_checked_at
            plain checked ? "Last scheduler check: #{checked.in_time_zone.strftime("%b %-d, %H:%M %Z")}." :
              "The scheduler has not checked this configuration yet."
          end
          if @schedule.last_error_code
            p(role: "status", class: "mt-3 text-sm text-red-800") do
              plain "#{@schedule.last_error_code.humanize}. Review the latest import in administration."
            end
          end
          p(class: "mt-4 text-sm text-stone-600") do
            plain "Running imports are never overlapped. Failed imports wait for review."
            plain " A successful import establishes the first history baseline without creating events."
          end
        end
      end
    end
  end
end
