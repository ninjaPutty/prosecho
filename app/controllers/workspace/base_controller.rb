module Workspace
  class BaseController < StaffController
    before_action :require_workspace_access

    private

    def current_policy
      @current_policy ||= DataPolicy.current
    end

    def require_workspace_access
      allowed = current_user.campuses.active.exists?
      AccessEvent.create!(actor: current_user, resource: "dashboard",
        outcome: allowed ? "allowed" : "denied")
      head :forbidden unless allowed
    end
  end
end
