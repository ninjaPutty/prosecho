Devise.setup do |config|
  require "devise/orm/active_record"
  config.authentication_keys = [:email]
  config.case_insensitive_keys = [:email]
  config.strip_whitespace_keys = [:email]
  config.maximum_attempts = 5
  config.paranoid = true
  config.password_length = 8..128
  config.sign_out_via = :delete
  config.timeout_in = 30.minutes
  config.unlock_strategy = :time
  config.unlock_in = 30.minutes
end
