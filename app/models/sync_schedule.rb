class SyncSchedule < ApplicationRecord
  belongs_to :administrator, class_name: "User"
  validates :enabled, inclusion: {in: [true, false]}
  validates :interval_hours, numericality: {only_integer: true, greater_than: 0, less_than_or_equal_to: 168}
  validates :scheduled_at, presence: true
  validates :slot, inclusion: {in: [1]}

  def self.current
    find_by(slot: 1) || new(interval_hours: 24)
  end

  def due_at
    completed = PersonRefreshRun.where(all_campuses: true, status: "succeeded").maximum(:finished_at)
    scheduled = next_due_at || next_occurrence(inclusive: true)
    [scheduled, completed && next_occurrence(completed)].compact.max
  end

  def next_occurrence(from = Time.current, inclusive: false)
    scheduled = Time.utc(from.year, from.month, from.day, scheduled_at.hour, scheduled_at.min)
    return scheduled if inclusive && scheduled >= from
    return scheduled if !inclusive && scheduled > from

    scheduled + 1.day
  end

  def health
    return "disabled" unless enabled?
    return "blocked" if last_error_code && last_error_code != "refresh_in_progress"
    completed = PersonRefreshRun.where(all_campuses: true, status: "succeeded").maximum(:finished_at)
    if PersonRefreshRun.active.exists?
      return (completed && completed < 2.days.ago) ? "running_stale" : "running"
    end
    return "baseline_pending" unless completed
    (completed < 2.days.ago) ? "stale" : "healthy"
  end

  def record_status!(**attributes)
    # Scheduler heartbeats must not invalidate the administrator's form revision.
    # Configuration saves still use optimistic locking; operational writes occur
    # under the scheduler's row lock and touch only these metadata columns.
    update_columns(attributes.slice(:last_checked_at, :last_enqueued_at, :last_error_code, :next_due_at))
  end
end
