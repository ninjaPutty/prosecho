module Workspace
  class RefreshesController < BaseController
    def create
      selected = session.dig(:people_filters, "campus_id")
      run = if params[:resume_run_id].present?
        PersonRefreshRun.where(actor: current_user).find(params[:resume_run_id]).resume!
      else
        PersonRefreshRun.active.find_by(actor: current_user) || PersonRefreshRun.start!(actor: current_user,
          campus_ids: selected.present? ? [selected] : nil)
      end
      dispatched = run.dispatch!
      message = dispatched ? "Refresh queued from its saved checkpoint." : "Refresh is already scheduled or processing."
      redirect_to dashboard_path, notice: "#{message} Your current directory stays available.",
        status: :see_other
    rescue PersonRefreshRun::NotReady, PersonRefreshRun::AlreadyRunning => error
      redirect_to dashboard_path, alert: error.message, status: :see_other
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
  end
end
