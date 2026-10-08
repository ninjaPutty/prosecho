class AddRefreshCheckpoints < ActiveRecord::Migration[8.1]
  def change
    add_column :person_refresh_runs, :next_offset, :integer, null: false, default: 0
    add_column :person_refresh_runs, :read_complete, :boolean, null: false, default: false
    add_column :person_refresh_runs, :job_id, :string
    add_column :person_refresh_runs, :retry_at, :datetime
    add_column :person_refresh_runs, :last_progress_at, :datetime
  end
end
