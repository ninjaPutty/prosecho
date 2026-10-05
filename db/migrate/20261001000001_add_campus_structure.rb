class AddCampusStructure < ActiveRecord::Migration[8.1]
  def change
    add_column :campuses, :active, :boolean, null: false, default: true
    add_reference :campuses, :parent, type: :uuid, foreign_key: {to_table: :campuses}
  end
end
