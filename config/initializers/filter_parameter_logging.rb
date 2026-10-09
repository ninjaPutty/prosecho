# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  :address, :birth_date, :phone, :latitude, :longitude, :filters, :search, :town,
  :first_name, :last_name, :nick_name, :display_name, :payload, :state, :city, :min_age, :max_age,
  :previous_value, :current_value, :details, :household, :custom_attributes
]

# HTTP filtering does not automatically redact Active Record inspection or SQL
# bind logging. History snapshots and event values must be filtered there too.
ActiveSupport.on_load(:active_record) do
  self.filter_attributes += Rails.application.config.filter_parameters
end
