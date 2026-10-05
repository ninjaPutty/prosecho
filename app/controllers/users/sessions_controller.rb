module Users
  class SessionsController < Devise::SessionsController
    before_action :private_response
    rate_limit to: 10, within: 5.minutes, only: :create

    def new
      self.resource = resource_class.new(sign_in_params)
      clean_up_passwords(resource)
      render Components::SignIn.new(message: flash[:alert])
    end

    private

    def private_response
      response.headers["Cache-Control"] = "private, no-store"
    end
  end
end
