module Workspace
  class RefreshesController < StaffController
    before_action :require_refresh_administrator

    def create
      if params[:resume_run_id].present?
        saved = PersonRefreshRun.where(actor: current_user).find(params[:resume_run_id]).resume!
        saved.dispatch!
      else
        PersonRefreshRun.enqueue!(actor: current_user)
      end
      redirect_to refresh_return_path,
        notice: "All-campus refresh queued or processing from its saved checkpoint. " \
          "Your current directory stays available.",
        status: :see_other
    rescue PersonRefreshRun::NotReady, PersonRefreshRun::AlreadyRunning => error
      redirect_to refresh_return_path, alert: error.message, status: :see_other
    end

    def show
      run = PersonRefreshRun.where(actor: current_user).order(created_at: :desc).first
      render json: {
        status: run&.status, page_count: run&.page_count,
        staged_count: run&.entries&.count, error_code: run&.error_code,
        duplicate_count: run&.duplicate_count, error_details: run&.diagnostic_details,
        error_message: run&.error_message, resumable: run&.resumable?,
        worker_online: Directory::WorkerHealth.online?
      }
    end

    private

    def refresh_return_path
      current_user.campuses.active.exists? ? dashboard_path : admin_root_path
    end

    def require_refresh_administrator
      allowed = current_user.administrator?
      AccessEvent.create!(actor: current_user, resource: "administration",
        outcome: allowed ? "allowed" : "denied")
      head :forbidden unless allowed
    end
  end
end
