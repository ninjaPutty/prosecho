module Workspace
  class FiltersController < BaseController
    def create
      values = params.fetch(:filters, ActionController::Parameters.new).permit(
        :campus_id, :connection_status,
        :min_age, :max_age, :town, :search
      ).to_h
      query = Directory::Query.new(actor: current_user, filters: values)
      if query.errors.any?
        render Components::Workspace::People.new(query: query, actor: current_user),
          status: :unprocessable_content
      else
        session[:people_filters] = values
        redirect_to dashboard_path, status: :see_other
      end
    end

    def destroy
      session.delete(:people_filters)
      redirect_to dashboard_path, status: :see_other
    end
  end
end
