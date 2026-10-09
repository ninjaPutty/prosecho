class AddPersonHistoryAndSyncSchedule < ActiveRecord::Migration[8.1]
  def change
    create_table :person_snapshots, id: :uuid do |t|
      t.references :person_profile, type: :uuid, null: false,
        foreign_key: {on_delete: :cascade}, index: {unique: true}
      t.references :refresh_run, type: :uuid, null: false,
        foreign_key: {to_table: :person_refresh_runs}
      t.references :campus, type: :uuid, null: false, foreign_key: true
      t.string :policy_revision, null: false
      t.string :campus_scope, array: true, default: [], null: false
      t.jsonb :state, default: {}, null: false
      t.datetime :observed_at, null: false
      t.timestamps
    end

    create_table :person_change_events, id: :uuid do |t|
      t.references :person_profile, type: :uuid, foreign_key: {on_delete: :nullify}
      t.references :refresh_run, type: :uuid, null: false,
        foreign_key: {to_table: :person_refresh_runs}
      t.references :campus, type: :uuid, null: false, foreign_key: true
      t.references :previous_campus, type: :uuid, null: false,
        foreign_key: {to_table: :campuses}
      t.string :source_system, null: false
      t.uuid :rock_guid, null: false
      t.integer :rock_id, null: false
      t.string :event_type, null: false
      t.string :policy_revision, null: false
      t.jsonb :previous_value, default: {}, null: false
      t.jsonb :current_value, default: {}, null: false
      t.jsonb :details, default: {}, null: false
      t.integer :related_campus_rock_ids, array: true, default: [], null: false
      t.boolean :household_reference_changed, default: false, null: false
      t.datetime :discovered_at, null: false
      t.timestamps
    end
    add_index :person_change_events, [:refresh_run_id, :rock_guid, :event_type], unique: true,
      name: "index_person_changes_once_per_run"
    add_index :person_change_events, [:campus_id, :policy_revision, :discovered_at],
      name: "index_person_changes_for_feed"

    create_table :sync_schedules, id: :uuid do |t|
      t.integer :slot, null: false, default: 1
      t.boolean :enabled, null: false, default: false
      t.integer :interval_hours, null: false, default: 24
      t.references :administrator, type: :uuid, null: false, foreign_key: {to_table: :users}
      t.datetime :next_due_at
      t.datetime :last_enqueued_at
      t.datetime :last_checked_at
      t.string :last_error_code
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :sync_schedules, :slot, unique: true
    add_check_constraint :sync_schedules, "slot = 1", name: "sync_schedule_singleton"
    add_check_constraint :sync_schedules, "interval_hours BETWEEN 1 AND 168",
      name: "sync_schedule_interval"
  end
end
