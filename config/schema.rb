# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_08_000001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "access_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "actor_id", null: false
    t.datetime "created_at", null: false
    t.string "outcome", null: false
    t.string "resource", null: false
    t.uuid "resource_id"
    t.index ["actor_id"], name: "index_access_events_on_actor_id"
  end

  create_table "campus_accesses", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "campus_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["campus_id"], name: "index_campus_accesses_on_campus_id"
    t.index ["user_id", "campus_id"], name: "index_campus_accesses_on_user_id_and_campus_id", unique: true
    t.index ["user_id"], name: "index_campus_accesses_on_user_id"
  end

  create_table "campuses", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.uuid "parent_id"
    t.integer "rock_id", null: false
    t.datetime "updated_at", null: false
    t.index ["parent_id"], name: "index_campuses_on_parent_id"
    t.index ["rock_id"], name: "index_campuses_on_rock_id", unique: true
  end

  create_table "data_policies", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "address_handling", default: "", null: false
    t.text "address_source", default: "", null: false
    t.string "attribute_keys", default: [], null: false, array: true
    t.integer "backup_retention_days"
    t.datetime "confirmed_at"
    t.uuid "confirmed_by_id"
    t.datetime "created_at", null: false
    t.text "family_status_meaning", default: "", null: false
    t.integer "history_retention_days"
    t.text "household_handling", default: "", null: false
    t.text "household_source", default: "", null: false
    t.integer "lock_version", default: 0, null: false
    t.integer "log_retention_days"
    t.integer "profile_retention_days"
    t.uuid "recorded_by_id", null: false
    t.text "retention_notes", default: "", null: false
    t.string "selected_fields", default: [], null: false, array: true
    t.integer "slot", default: 1, null: false
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.index ["confirmed_by_id"], name: "index_data_policies_on_confirmed_by_id"
    t.index ["recorded_by_id"], name: "index_data_policies_on_recorded_by_id"
    t.index ["slot"], name: "index_data_policies_on_slot", unique: true
    t.check_constraint "slot = 1", name: "data_policies_singleton"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'confirmed'::character varying::text])", name: "data_policies_status"
  end

  create_table "foundation_checks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.jsonb "blockers", default: [], null: false
    t.datetime "created_at", null: false
    t.boolean "ready", default: false, null: false
    t.datetime "updated_at", null: false
  end

  create_table "person_profiles", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.date "birth_date"
    t.uuid "campus_id", null: false
    t.string "city"
    t.integer "connection_status_id"
    t.string "connection_status_label"
    t.string "country"
    t.datetime "created_at", null: false
    t.jsonb "custom_attributes", default: {}, null: false
    t.string "display_name", null: false
    t.string "first_name"
    t.string "home_status", default: "missing", null: false
    t.jsonb "household", default: {}, null: false
    t.boolean "in_population", default: true, null: false
    t.jsonb "issues", default: [], null: false
    t.string "last_name"
    t.datetime "left_scope_at"
    t.integer "location_id"
    t.integer "marital_status_id"
    t.string "marital_status_label"
    t.string "nick_name"
    t.datetime "observed_at", null: false
    t.integer "photo_id"
    t.datetime "photo_observed_at"
    t.string "policy_revision", null: false
    t.jsonb "private_address", default: {}, null: false
    t.datetime "private_observed_at"
    t.uuid "rock_guid", null: false
    t.integer "rock_id", null: false
    t.string "source_created_at"
    t.string "source_modified_at"
    t.string "source_system", default: "rock.chapel.org", null: false
    t.string "state"
    t.datetime "updated_at", null: false
    t.index ["campus_id", "policy_revision", "in_population"], name: "index_person_profiles_for_directory"
    t.index ["campus_id"], name: "index_person_profiles_on_campus_id"
    t.index ["city"], name: "index_person_profiles_on_city"
    t.index ["connection_status_id"], name: "index_person_profiles_on_connection_status_id"
    t.index ["source_system", "rock_guid"], name: "index_person_profiles_on_source_system_and_rock_guid", unique: true
  end

  create_table "person_refresh_entries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "observed_at", null: false
    t.jsonb "payload", null: false
    t.uuid "rock_guid", null: false
    t.uuid "run_id", null: false
    t.datetime "updated_at", null: false
    t.index ["run_id", "rock_guid"], name: "index_person_refresh_entries_on_run_id_and_rock_guid", unique: true
    t.index ["run_id"], name: "index_person_refresh_entries_on_run_id"
  end

  create_table "person_refresh_runs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "actor_id", null: false
    t.string "campus_ids", default: [], null: false, array: true
    t.boolean "checkpoint_retained", default: false, null: false
    t.datetime "created_at", null: false
    t.integer "duplicate_count", default: 0, null: false
    t.string "error_code"
    t.jsonb "error_details", default: {}, null: false
    t.datetime "finished_at"
    t.integer "imported_count", default: 0, null: false
    t.string "job_id"
    t.datetime "last_progress_at"
    t.integer "last_rock_id"
    t.integer "next_offset", default: 0, null: false
    t.integer "page_count", default: 0, null: false
    t.string "policy_revision", null: false
    t.boolean "read_complete", default: false, null: false
    t.datetime "retry_at"
    t.integer "singleton_slot", default: 1, null: false
    t.datetime "started_at"
    t.string "status", default: "queued", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_person_refresh_runs_on_actor_id"
    t.index ["singleton_slot"], name: "index_person_refresh_runs_one_active", unique: true, where: "((status)::text = ANY (ARRAY[('queued'::character varying)::text, ('running'::character varying)::text]))"
  end

  create_table "solid_queue_batch_executions", force: :cascade do |t|
    t.bigint "batch_id", null: false
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.index ["batch_id"], name: "index_solid_queue_batch_executions_on_batch_id"
    t.index ["job_id"], name: "index_solid_queue_batch_executions_on_job_id", unique: true
  end

  create_table "solid_queue_batches", force: :cascade do |t|
    t.string "active_job_batch_id"
    t.integer "completed_jobs", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "description"
    t.datetime "enqueued_at"
    t.datetime "failed_at"
    t.integer "failed_jobs", default: 0, null: false
    t.datetime "finished_at"
    t.text "metadata"
    t.text "on_failure"
    t.text "on_finish"
    t.text "on_success"
    t.integer "total_jobs", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_batch_id"], name: "index_solid_queue_batches_on_active_job_batch_id", unique: true
    t.index ["finished_at"], name: "index_solid_queue_batches_on_finished_at"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.bigint "batch_id"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["batch_id"], name: "index_solid_queue_jobs_on_batch_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "encrypted_password", null: false
    t.integer "failed_attempts", default: 0, null: false
    t.datetime "locked_at"
    t.string "role", default: "staff", null: false
    t.datetime "updated_at", null: false
    t.boolean "view_history", default: false, null: false
    t.boolean "view_locations", default: false, null: false
    t.boolean "view_photos", default: false, null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.check_constraint "role::text = ANY (ARRAY['administrator'::character varying::text, 'staff'::character varying::text])", name: "users_role"
  end

  add_foreign_key "access_events", "users", column: "actor_id"
  add_foreign_key "campus_accesses", "campuses"
  add_foreign_key "campus_accesses", "users"
  add_foreign_key "campuses", "campuses", column: "parent_id"
  add_foreign_key "data_policies", "users", column: "confirmed_by_id"
  add_foreign_key "data_policies", "users", column: "recorded_by_id"
  add_foreign_key "person_profiles", "campuses"
  add_foreign_key "person_refresh_entries", "person_refresh_runs", column: "run_id", on_delete: :cascade
  add_foreign_key "person_refresh_runs", "users", column: "actor_id"
  add_foreign_key "solid_queue_batch_executions", "solid_queue_batches", column: "batch_id", on_delete: :cascade
  add_foreign_key "solid_queue_batch_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
end
