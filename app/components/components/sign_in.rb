module Components
  class SignIn < Phlex::HTML
    def initialize(message: nil)
      @message = message
    end

    def view_template
      doctype
      html(lang: "en") do
        head do
          meta(charset: "utf-8")
          meta(name: "viewport", content: "width=device-width, initial-scale=1")
          title { "Staff sign in | Prosecho" }
          link(rel: "stylesheet", href: view_context.asset_path("tailwind.css"))
        end
        body(class: "bg-stone-50 text-stone-900") do
          main(class: "mx-auto max-w-md px-6 py-20") do
            h1(class: "text-3xl font-semibold") { "Welcome back" }
            p(class: "my-4 text-stone-600") { "Sign in with your Chapel staff account." }
            p(role: "alert", class: "my-4 text-red-700") { @message } if @message.present?
            form(action: view_context.user_session_path, method: "post", class: "space-y-5") do
              input(type: "hidden", name: "authenticity_token",
                value: view_context.form_authenticity_token)
              label(for: "email", class: "block") { "Email" }
              input(id: "email", name: "user[email]", type: "email", autocomplete: "username",
                required: true, class: "w-full rounded border p-3")
              label(for: "password", class: "block") { "Password" }
              input(id: "password", name: "user[password]", type: "password",
                autocomplete: "current-password", required: true, class: "w-full rounded border p-3")
              button(type: "submit", class: "w-full rounded bg-teal-800 p-3 text-white") { "Sign in" }
            end
            p(class: "mt-8 text-sm text-stone-600") do
              plain "Accounts are provisioned by your administrator. Contact them for access."
            end
          end
        end
      end
    end
  end
end
