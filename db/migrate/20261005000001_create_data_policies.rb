class CreateDataPolicies < ActiveRecord::Migration[8.1]
  def change
    create_table :data_policies, id: :uuid do |t|
      t.text :address_handling, default: "", null: false
      t.text :address_source, default: "", null: false
      t.string :attribute_keys, array: true, default: [], null: false
      t.integer :backup_retention_days
      t.datetime :confirmed_at
      t.references :confirmed_by, type: :uuid, foreign_key: {to_table: :users}
      t.text :family_status_meaning, default: "", null: false
      t.integer :history_retention_days
      t.text :household_handling, default: "", null: false
      t.text :household_source, default: "", null: false
      t.integer :lock_version, default: 0, null: false
      t.integer :log_retention_days
      t.integer :profile_retention_days
      t.references :recorded_by, type: :uuid, null: false, foreign_key: {to_table: :users}
      t.text :retention_notes, default: "", null: false
      t.string :selected_fields, array: true, default: [], null: false
      t.integer :slot, default: 1, null: false
      t.string :status, default: "draft", null: false
      t.timestamps
    end
    add_index :data_policies, :slot, unique: true
    add_check_constraint :data_policies, "slot = 1", name: "data_policies_singleton"
    add_check_constraint :data_policies, "status IN ('draft', 'confirmed')",
      name: "data_policies_status"
  end
end
