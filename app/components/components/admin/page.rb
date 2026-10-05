module Components
  module Admin
    class Page < Phlex::HTML
      BUTTON = "inline-block rounded-lg bg-teal-800 px-5 py-3 font-medium text-white".freeze
      INPUT = "mt-2 w-full rounded-lg border border-stone-300 bg-white px-3 py-2".freeze

      private

      def errors_for(record)
        return if record.errors.empty?

        div(role: "alert", class: "my-6 rounded-lg border border-red-200 bg-red-50 p-4") do
          h2(class: "font-semibold") { "Please check these details" }
          ul { record.errors.full_messages.each { |message| li { message } } }
        end
      end

      def field(label:, name:, value: nil, type: "text", required: false)
        id = name.gsub(/[^a-z0-9]/i, "_")
        div do
          label(for: id, class: "block font-medium") { label }
          attributes = {id: id, name: name, type: type, required: required, class: INPUT}
          if type == "password"
            attributes[:autocomplete] = "new-password"
          else
            attributes[:value] = value
          end
          input(**attributes)
        end
      end

      def page(title, setup: false)
        doctype
        html(lang: "en") do
          head do
            meta(charset: "utf-8")
            meta(name: "viewport", content: "width=device-width, initial-scale=1")
            title { "#{title} | Prosecho" }
            link(rel: "stylesheet", href: view_context.asset_path("tailwind.css"))
          end
          body(class: "min-h-screen bg-stone-50 text-stone-900") do
            main(class: "mx-auto max-w-5xl px-6 py-10") do
              unless setup
                nav(class: "mb-8 flex flex-wrap items-center gap-5",
                  aria_label: "Administration") do
                  a(href: view_context.admin_root_path, class: "font-semibold text-teal-800") do
                    plain "Account administration"
                  end
                  a(href: view_context.dashboard_path) { "Pastoral workspace" }
                  post_form(action: view_context.destroy_user_session_path, method: "delete") do
                    button(type: "submit", class: "underline") { "Sign out" }
                  end
                end
              end
              h1(class: "mb-3 text-3xl font-semibold tracking-tight") { title }
              if view_context.flash[:notice].present?
                p(role: "status", class: "my-4 rounded-lg bg-teal-50 p-4") do
                  plain view_context.flash[:notice]
                end
              end
              if view_context.flash[:alert].present?
                p(role: "alert", class: "my-4 rounded-lg bg-red-50 p-4 text-red-800") do
                  plain view_context.flash[:alert]
                end
              end
              yield
            end
          end
        end
      end

      def post_form(action:, method: "post", &block)
        form(action: action, method: "post", class: "space-y-5") do
          input(type: "hidden", name: "authenticity_token",
            value: view_context.form_authenticity_token)
          input(type: "hidden", name: "_method", value: method) unless method == "post"
          block.call
        end
      end

      def toggle(label:, name:, checked:)
        id = name.gsub(/[^a-z0-9]/i, "_")
        input(type: "hidden", name: name, value: "0")
        label(for: id, class: "flex items-center gap-3") do
          input(id: id, type: "checkbox", name: name, value: "1", checked: checked)
          plain label
        end
      end
    end
  end
end
