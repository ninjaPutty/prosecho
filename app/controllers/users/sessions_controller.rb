module Users
  class SessionsController < Devise::SessionsController
    before_action :private_response
    rate_limit to: 10, within: 5.minutes, only: :create

    def new
      self.resource = resource_class.new(sign_in_params)
      clean_up_passwords(resource)
      render Components::SignIn.new(message: flash[:alert])
    end

    def create
      session.delete(:pending_authenticator_user_id)
      self.resource = warden.authenticate(auth_options.merge(store: false))
      return invalid_credentials unless resource

      sign_out(resource_name)
      reset_session
      session[:pending_authenticator_user_id] = resource.id
      session[:pending_authenticator_salt] = resource.authenticatable_salt
      session[:pending_authenticator_started_at] = Time.current.to_i
      redirect_to new_authenticator_path
    end

    private

    def complete_sign_in
      set_flash_message(:notice, :signed_in) if is_flashing_format?
      # Warden has already authenticated without storing a session; force persistence here.
      sign_in(resource_name, resource, force: true)
      respond_with resource, location: after_sign_in_path_for(resource)
    end

    def invalid_credentials
      flash.now[:alert] = "Invalid email or password."
      self.resource = resource_class.new(sign_in_params)
      clean_up_passwords(resource)
      render Components::SignIn.new(message: flash[:alert]), status: :unprocessable_content
    end

    def private_response
      response.headers["Cache-Control"] = "private, no-store"
    end
  end
end
