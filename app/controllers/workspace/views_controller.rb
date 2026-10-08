module Workspace
  class ViewsController < BaseController
    def changes
      render Components::Workspace::Pending.new(view: :changes)
    end

    def map
      render Components::Workspace::Pending.new(view: :map)
    end
  end
end
