class AddAuthenticatorRecoveryCodes < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :otp_recovery_code_digests, :string, array: true, default: [], null: false
  end
end
