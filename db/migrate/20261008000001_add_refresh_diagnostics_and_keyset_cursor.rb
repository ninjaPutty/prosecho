class AddRefreshDiagnosticsAndKeysetCursor < ActiveRecord::Migration[8.1]
  def change
    add_column :person_refresh_runs, :checkpoint_retained, :boolean, null: false, default: false
    add_column :person_refresh_runs, :duplicate_count, :integer, null: false, default: 0
    add_column :person_refresh_runs, :error_details, :jsonb, null: false, default: {}
    add_column :person_refresh_runs, :last_rock_id, :integer
  end
end
