class DashboardController < StaffController
  def show
    allowed = current_user.active? && current_user.campuses.active.exists?
    AccessEvent.create!(actor: current_user, resource: "dashboard",
      outcome: allowed ? "allowed" : "denied")
    return head :forbidden unless allowed

    render Components::FoundationDashboard.new(campuses: current_user.campuses.active.order(:name))
  end
end
