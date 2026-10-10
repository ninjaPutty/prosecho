module Admin
  class SyncSchedulesController < BaseController
    def show
      render Components::Admin::SyncScheduleForm.new(schedule: SyncSchedule.current)
    end

    def update
      schedule = SyncSchedule.current
      if schedule.persisted? && params.require(:sync_schedule)[:revision] != schedule.lock_version.to_s
        return render Components::Admin::SyncScheduleForm.new(schedule: schedule), status: :conflict
      end
      schedule.assign_attributes(params.require(:sync_schedule).permit(:enabled, :scheduled_at))
      schedule.administrator = current_user
      schedule.next_due_at = schedule.next_occurrence if schedule.scheduled_at
      schedule.last_error_code = nil
      SyncSchedule.transaction(requires_new: true) do
        schedule.save!
        AccessEvent.create!(actor: current_user, resource: "administration",
          resource_id: schedule.id, outcome: "updated")
      end
      redirect_to admin_sync_schedule_path, notice: "Refresh schedule saved."
    rescue ActiveRecord::RecordInvalid
      render Components::Admin::SyncScheduleForm.new(schedule: schedule), status: :unprocessable_content
    rescue ActiveRecord::StaleObjectError, ActiveRecord::RecordNotUnique
      render Components::Admin::SyncScheduleForm.new(schedule: SyncSchedule.current), status: :conflict
    end
  end
end
