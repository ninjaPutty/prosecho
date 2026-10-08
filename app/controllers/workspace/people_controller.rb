module Workspace
  class PeopleController < BaseController
    def show
      person = PersonProfile.visible_to(current_user, policy: current_policy).find(params[:id])
      AccessEvent.create!(actor: current_user, resource: "directory", resource_id: person.id,
        outcome: "allowed")
      component = Components::Workspace::Person.new(
        person_view: Directory::PersonView.new(person: person, actor: current_user),
        frame: request.headers["Turbo-Frame"] == "person_details"
      )
      render component, layout: false
    end
  end
end
