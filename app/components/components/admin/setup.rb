module Components
  module Admin
    class Setup < Page
      def initialize(user:)
        @user = user
      end

      def view_template
        page("Set up Prosecho", setup: true) do
          p(class: "mb-6 text-stone-600") do
            plain "Create the first account. It will have account administration access."
          end
          errors_for(@user)
          div(class: "max-w-lg rounded-xl bg-white p-6 shadow-sm") do
            post_form(action: view_context.admin_setup_path) do
              field(label: "Email", name: "user[email]", value: @user.email,
                type: "email", required: true)
              field(label: "Password (8-128 characters)", name: "user[password]",
                type: "password", required: true)
              field(label: "Confirm password", name: "user[password_confirmation]",
                type: "password", required: true)
              button(type: "submit", class: BUTTON) { "Create administrator" }
            end
          end
        end
      end
    end
  end
end
