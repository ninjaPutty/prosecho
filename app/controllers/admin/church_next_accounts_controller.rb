module Admin
  class ChurchNextAccountsController < BaseController
    def index
      query = ChurchNext::ReviewQuery.new(actor: current_user, page: params.fetch(:page, 1))
      render Components::Workspace::ChurchNextAccounts.new(query: query, actor: current_user)
    end

    def photo
      account = ChurchNextAccount.find(params[:id])
      policy = DataPolicy.current
      return head :forbidden unless current_user.view_photos? && policy.confirmed? && policy.valid? &&
        policy.selected_fields.include?("photo")
      return head :not_found unless account.photo_available?

      image = Rails.cache.fetch(["private-churchnext-photo", account.external_user_id], expires_in: 10.minutes) do
        Integrations::ChurchNext::Client.new.photo(account.external_user_id)
      end
      AccessEvent.create!(actor: current_user, resource: "church_next_accounts",
        resource_id: account.id, outcome: "allowed")
      send_data image.body, type: image.content_type, disposition: "inline"
    rescue Integrations::ChurchNext::Client::ConfigurationError,
      Integrations::ChurchNext::Client::RequestError
      head :not_found
    end
  end
end
