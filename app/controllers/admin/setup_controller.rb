module Admin
  class SetupController < ApplicationController
    before_action :private_response
    rate_limit to: 10, within: 5.minutes, only: :create
    rescue_from ActionController::InvalidAuthenticityToken, with: :refresh_setup_session

    def create
      values = params.require(:user).permit(:email, :password, :password_confirmation)
      user = Access::Provisioner.bootstrap(email: values[:email], password: values[:password],
        password_confirmation: values.fetch(:password_confirmation, ""))
      sign_in(user)
      redirect_to admin_root_path, notice: "Your administrator account is ready."
    rescue ActiveRecord::RecordInvalid => error
      render Components::Admin::Setup.new(user: error.record), status: :unprocessable_content
    rescue Access::Provisioner::NotAuthorized
      head :conflict
    end

    private

    def private_response
      response.headers["Cache-Control"] = "private, no-store"
    end

    def refresh_setup_session
      private_response
      return head :conflict if User.exists?

      # A stale token must never reach provisioning or be retried with submitted
      # passwords. Rotate the session and require a new, verified form submission.
      reset_session
      user = User.new
      user.errors.add(:base,
        "Your setup session expired or changed. Please re-enter and confirm your password.")
      render Components::Admin::Setup.new(user: user), status: :unprocessable_content
    end
  end
end
