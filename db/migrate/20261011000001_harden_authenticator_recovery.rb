class HardenAuthenticatorRecovery < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :otp_required, :boolean, default: false, null: false
    add_column :users, :otp_failed_attempts, :integer, default: 0, null: false
    add_column :users, :otp_session_version, :string, default: "", null: false
  end
end
