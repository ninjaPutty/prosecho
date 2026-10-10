class AddGmtTimeToSyncSchedules < ActiveRecord::Migration[8.1]
  def change
    add_column :sync_schedules, :scheduled_at, :time, null: false, default: "00:00:00"
  end
end
