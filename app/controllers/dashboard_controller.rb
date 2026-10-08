class DashboardController < Workspace::BaseController
  def show
    query = Directory::Query.new(actor: current_user, filters: session[:people_filters] || {},
      page: params.fetch(:page, 1))
    runs = PersonRefreshRun.where(actor: current_user).order(created_at: :desc).limit(1)
    render Components::Workspace::People.new(query: query, actor: current_user, run: runs.first)
  end
end
