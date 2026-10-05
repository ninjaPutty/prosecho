class StaffController < ApplicationController
  before_action :authenticate_user!
  before_action :active_account
  before_action :private_response

  private

  def active_account
    unless current_user.active? && !current_user.access_locked?
      sign_out current_user
      redirect_to new_user_session_path
    end
  end

  def authorize_campus!(campus_id, capability)
    allowed = current_user.can_access?(campus_id, capability)
    resource = (capability == :directory) ? "dashboard" : capability.to_s
    AccessEvent.create!(actor: current_user, resource: resource,
      resource_id: campus_id, outcome: allowed ? "allowed" : "denied")
    head :forbidden unless allowed
    allowed
  end

  def private_response
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["Referrer-Policy"] = "same-origin"
  end
end
