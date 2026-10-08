class CreatePersonDirectory < ActiveRecord::Migration[8.1]
  def change
    create_table :person_profiles, id: :uuid do |t|
      t.references :campus, type: :uuid, null: false, foreign_key: true
      t.string :source_system, default: "rock.chapel.org", null: false
      t.integer :rock_id, null: false
      t.uuid :rock_guid, null: false
      t.string :first_name
      t.string :last_name
      t.string :nick_name
      t.string :display_name, null: false
      t.date :birth_date
      t.integer :connection_status_id
      t.string :connection_status_label
      t.integer :marital_status_id
      t.string :marital_status_label
      t.integer :photo_id
      t.string :home_status, default: "missing", null: false
      t.integer :location_id
      t.string :city
      t.string :state
      t.string :country
      t.jsonb :private_address, default: {}, null: false
      t.jsonb :household, default: {}, null: false
      t.jsonb :custom_attributes, default: {}, null: false
      t.jsonb :issues, default: [], null: false
      t.string :policy_revision, null: false
      t.datetime :observed_at, null: false
      t.datetime :private_observed_at
      t.datetime :photo_observed_at
      t.string :source_created_at
      t.string :source_modified_at
      t.boolean :in_population, default: true, null: false
      t.datetime :left_scope_at
      t.timestamps
    end
    add_index :person_profiles, [:source_system, :rock_guid], unique: true
    add_index :person_profiles, [:campus_id, :policy_revision, :in_population],
      name: "index_person_profiles_for_directory"
    add_index :person_profiles, :city
    add_index :person_profiles, :connection_status_id

    create_table :person_refresh_runs, id: :uuid do |t|
      t.references :actor, type: :uuid, null: false, foreign_key: {to_table: :users}
      t.string :campus_ids, array: true, default: [], null: false
      t.string :policy_revision, null: false
      t.string :status, default: "queued", null: false
      t.integer :singleton_slot, default: 1, null: false
      t.integer :imported_count, default: 0, null: false
      t.integer :page_count, default: 0, null: false
      t.string :error_code
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :person_refresh_runs, :singleton_slot, unique: true,
      where: "status IN ('queued', 'running')", name: "index_person_refresh_runs_one_active"

    create_table :person_refresh_entries, id: :uuid do |t|
      t.references :run, type: :uuid, null: false,
        foreign_key: {to_table: :person_refresh_runs, on_delete: :cascade}
      t.uuid :rock_guid, null: false
      t.jsonb :payload, null: false
      t.datetime :observed_at, null: false
      t.timestamps
    end
    add_index :person_refresh_entries, [:run_id, :rock_guid], unique: true
  end
end
