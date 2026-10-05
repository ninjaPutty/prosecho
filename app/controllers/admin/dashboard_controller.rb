module Admin
  class DashboardController < BaseController
    prepend_before_action :offer_initial_setup

    def show
      page = params.fetch(:page, "1").to_i.clamp(1, 10000)
      accounts = User.order(:email).includes(:campuses).limit(30).offset((page - 1) * 30)
      render Components::Admin::Dashboard.new(accounts: accounts,
        campuses: Campus.includes(:parent).order(:name), page: page)
    end

    private

    def offer_initial_setup
      return if User.exists?

      private_response
      render Components::Admin::Setup.new(user: User.new)
    end
  end
end
