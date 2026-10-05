module Components
  class FoundationDashboard < Phlex::HTML
    def initialize(campuses:)
      @campuses = campuses
    end

    def view_template
      doctype
      html(lang: "en") do
        head do
          meta(charset: "utf-8")
          meta(name: "viewport", content: "width=device-width, initial-scale=1")
          title { "People at a glance | Prosecho" }
          link(rel: "stylesheet", href: view_context.asset_path("tailwind.css"))
        end
        body(class: "bg-stone-50 text-stone-900") do
          main(class: "mx-auto max-w-4xl px-6 py-16") do
            h1(class: "text-3xl font-semibold") { "People at a glance" }
            p(class: "my-4 text-stone-600") do
              plain "The pastoral workspace is being prepared. No live Rock data has been loaded."
            end
            h2(class: "mt-8 text-xl font-semibold") { "Your campuses" }
            ul(class: "my-4 space-y-2") { @campuses.each { |campus| li { campus.name } } }
            if view_context.current_user.administrator?
              a(href: view_context.admin_root_path, class: "mb-6 inline-block text-teal-800 underline") do
                plain "Account administration"
              end
            end
            form(action: view_context.destroy_user_session_path, method: "post") do
              input(type: "hidden", name: "_method", value: "delete")
              input(type: "hidden", name: "authenticity_token",
                value: view_context.form_authenticity_token)
              button(type: "submit", class: "rounded bg-teal-800 px-5 py-3 text-white") { "Sign out" }
            end
          end
        end
      end
    end
  end
end
