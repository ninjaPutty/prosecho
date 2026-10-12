class CreateChurchNextLinking < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pg_trgm"
    add_column :person_profiles, :email, :string
    add_column :person_profiles, :churchnext_user_id, :string
    add_index :person_profiles, :email
    add_index :person_profiles, :churchnext_user_id, unique: true,
      where: "churchnext_user_id IS NOT NULL"
    add_index :person_profiles, :last_name, using: :gin, opclass: :gin_trgm_ops

    create_table :church_next_accounts, id: :uuid do |t|
      t.string :external_user_id, null: false
      t.string :first_name, null: false
      t.string :last_name, null: false
      t.string :email, null: false
      t.boolean :email_verified, null: false, default: false
      t.boolean :photo_available, null: false, default: false
      t.string :status, null: false, default: "pending"
      t.references :person_profile, type: :uuid, foreign_key: {on_delete: :nullify}
      t.datetime :linked_at
      t.timestamps
    end
    add_index :church_next_accounts, :external_user_id, unique: true

    create_table :church_next_candidates, id: :uuid do |t|
      t.references :church_next_account, type: :uuid, null: false, foreign_key: true
      t.references :person_profile, type: :uuid, foreign_key: {on_delete: :nullify}
      t.string :rock_guid, null: false
      t.string :policy_revision, null: false
      t.integer :score, null: false
      t.string :reason, null: false
      t.string :status, null: false, default: "pending"
      t.references :reviewed_by, type: :uuid, foreign_key: {to_table: :users, on_delete: :nullify}
      t.datetime :decided_at
      t.timestamps
    end
    add_index :church_next_candidates, [:church_next_account_id, :rock_guid], unique: true

    create_table :church_next_link_deliveries, id: :uuid do |t|
      t.references :church_next_account, type: :uuid, null: false, foreign_key: true, index: {unique: true}
      t.uuid :prosecho_person_id, null: false
      t.string :status, null: false, default: "pending"
      t.integer :attempts, null: false, default: 0
      t.datetime :next_attempt_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :delivered_at
      t.string :last_error_code
      t.timestamps
    end
    add_index :church_next_link_deliveries, [:status, :next_attempt_at]
  end
end
