class RequireAuthenticatorForEveryUser < ActiveRecord::Migration[8.1]
  def change
    change_column_default :users, :otp_required, from: false, to: true
    execute "UPDATE users SET otp_required = TRUE"
  end
end
