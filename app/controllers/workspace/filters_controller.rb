module Workspace
  class FiltersController < BaseController
    def create
      values = params.fetch(:filters, ActionController::Parameters.new).permit(
        :campus_id, :connection_status,
        :min_age, :max_age, :town, :search, :change_days
      ).to_h
      changes = params[:view] == "changes"
      return head :forbidden if changes && !current_user.view_history?
      query = if changes
        Directory::ChangesQuery.new(actor: current_user, filters: values)
      else
        Directory::Query.new(actor: current_user, filters: values)
      end
      if query.errors.any?
        component = changes ? Components::Workspace::Changes : Components::Workspace::People
        render component.new(query: query, actor: current_user),
          status: :unprocessable_content
      else
        session[:people_filters] = values
        redirect_to changes ? workspace_changes_path : dashboard_path, status: :see_other
      end
    end

    def destroy
      session.delete(:people_filters)
      redirect_to (params[:view] == "changes") ? workspace_changes_path : dashboard_path, status: :see_other
    end
  end
end
