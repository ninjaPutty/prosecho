module Workspace
  class ViewsController < BaseController
    def changes
      unless current_user.view_history?
        AccessEvent.create!(actor: current_user, resource: "history", outcome: "denied")
        return head :forbidden
      end
      query = Directory::ChangesQuery.new(actor: current_user, filters: session[:people_filters] || {},
        page: params.fetch(:page, 1))
      AccessEvent.create!(actor: current_user, resource: "history", outcome: "allowed")
      render Components::Workspace::Changes.new(query: query, actor: current_user)
    end

    def map
      render Components::Workspace::Pending.new(view: :map)
    end
  end
end
