class MarkAllCampusRefreshRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :person_refresh_runs, :all_campuses, :boolean, null: false, default: false
  end
end
