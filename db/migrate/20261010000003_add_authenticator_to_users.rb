class AddAuthenticatorToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :otp_enabled_at, :datetime
    add_column :users, :otp_last_used_at, :datetime
    add_column :users, :otp_secret_ciphertext, :text
  end
end
