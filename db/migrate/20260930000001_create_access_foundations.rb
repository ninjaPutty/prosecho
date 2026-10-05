class CreateAccessFoundations < ActiveRecord::Migration[8.1]
  def change
    create_table :users, id: :uuid do |t|
      t.boolean :active, default: true, null: false
      t.string :email, null: false
      t.string :encrypted_password, null: false
      t.integer :failed_attempts, default: 0, null: false
      t.datetime :locked_at
      t.string :role, default: "staff", null: false
      t.boolean :view_history, default: false, null: false
      t.boolean :view_locations, default: false, null: false
      t.boolean :view_photos, default: false, null: false
      t.timestamps
    end
    add_index :users, :email, unique: true
    add_check_constraint :users, "role IN ('administrator', 'staff')", name: "users_role"

    create_table :campuses, id: :uuid do |t|
      t.string :name, null: false
      t.integer :rock_id, null: false
      t.timestamps
    end
    add_index :campuses, :rock_id, unique: true

    create_table :campus_accesses, id: :uuid do |t|
      t.references :campus, type: :uuid, null: false, foreign_key: true
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.timestamps
    end
    add_index :campus_accesses, [:user_id, :campus_id], unique: true

    create_table :access_events, id: :uuid do |t|
      t.references :actor, type: :uuid, null: false, foreign_key: {to_table: :users}
      t.string :outcome, null: false
      t.string :resource, null: false
      t.uuid :resource_id
      t.datetime :created_at, null: false
    end

    create_table :foundation_checks, id: :uuid do |t|
      t.jsonb :blockers, default: [], null: false
      t.boolean :ready, default: false, null: false
      t.timestamps
    end
  end
end
