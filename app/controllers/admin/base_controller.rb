module Admin
  class BaseController < StaffController
    before_action :require_administrator
    rescue_from Access::Provisioner::NotAuthorized, with: -> { head :forbidden }

    private

    def provisioner
      Access::Provisioner.new(actor: current_user)
    end

    def require_administrator
      allowed = current_user.administrator?
      AccessEvent.create!(actor: current_user, resource: "administration",
        outcome: allowed ? "allowed" : "denied")
      head :forbidden unless allowed
    end
  end
end
