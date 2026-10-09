class ScheduledPersonRefreshJob < ApplicationJob
  queue_as :foundation

  def perform
    schedule = SyncSchedule.find_by(slot: 1)
    return unless schedule&.enabled?

    schedule.with_lock do
      return unless schedule.enabled?
      schedule.record_status!(last_checked_at: Time.current)
      actor = schedule.administrator.reload
      if !actor.administrator? || actor.access_locked?
        schedule.record_status!(last_error_code: "administrator_unavailable")
      elsif !Pastoral::Configuration.load.directory_ready?
        schedule.record_status!(last_error_code: "directory_not_ready")
      elsif PersonRefreshRun.active.exists?
        schedule.record_status!(last_error_code: "refresh_in_progress")
      elsif PersonRefreshRun.where(all_campuses: true).order(created_at: :desc).first&.status == "failed"
        schedule.record_status!(last_error_code: "failed_refresh_needs_review")
      else
        schedule.record_status!(last_error_code: nil)
        return if schedule.due_at.future?
        PersonRefreshRun.enqueue!(actor: actor)
        schedule.record_status!(last_enqueued_at: Time.current,
          next_due_at: schedule.interval_hours.hours.from_now, last_error_code: nil)
      end
    end
  rescue PersonRefreshRun::AlreadyRunning
    schedule.with_lock { schedule.record_status!(last_error_code: "refresh_in_progress", last_checked_at: Time.current) }
  rescue PersonRefreshRun::NotReady
    schedule.with_lock { schedule.record_status!(last_error_code: "directory_not_ready", last_checked_at: Time.current) }
  end
end
