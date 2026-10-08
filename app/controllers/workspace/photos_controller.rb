module Workspace
  class PhotosController < BaseController
    def show
      scope = PersonProfile.visible_to(current_user, policy: current_policy)
      person = scope.find(params[:person_id])
      return head :forbidden unless current_policy.selected_fields.include?("photo") &&
        current_user.can_access?(person.campus_id, :photos)
      return head :not_found unless person.photo_id

      image = Rails.cache.fetch(["private-rock-photo", person.photo_id], expires_in: 10.minutes) do
        Integrations::Rock::ReadClient.new.photo(person.photo_id)
      end
      AccessEvent.create!(actor: current_user, resource: "photos", resource_id: person.id,
        outcome: "allowed")
      send_data image.body, type: image.content_type, disposition: "inline"
    rescue Integrations::Rock::ReadClient::ReadError,
      Integrations::Rock::ReadClient::ConfigurationError
      head :not_found
    end
  end
end
