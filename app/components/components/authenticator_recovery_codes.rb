module Components
  class AuthenticatorRecoveryCodes < Components::Admin::Page
    def initialize(codes:)
      @codes = codes
    end

    def view_template
      page("Save your recovery codes") do
        p(class: "my-4 text-stone-600") do
          plain "Store these codes somewhere safe outside your phone. They are shown only once."
          plain " If your phone changes or is lost, use one after your password to enroll a new phone."
          plain " Recovery replaces the old authenticator and invalidates all old recovery codes."
        end
        ul(class: "my-6 space-y-2 rounded-lg bg-white p-6 font-mono") do
          @codes.each { |value| li { code { value } } }
        end
        a(href: view_context.dashboard_path, class: BUTTON) { "I've saved my codes" }
      end
    end
  end
end
