module Components
  module Workspace
    class Page < Phlex::HTML
      register_element :turbo_frame, tag: "turbo-frame"
      BUTTON = "inline-flex items-center justify-center gap-2 rounded-xl bg-teal-800 " \
        "px-4 py-3 text-sm font-semibold text-white hover:bg-teal-900 " \
        "focus:ring-2 focus:ring-teal-500"
      INPUT = "w-full rounded-xl border border-stone-200 bg-white px-3 py-2 text-sm " \
        "focus:border-teal-600 focus:outline-none focus:ring-2 focus:ring-teal-100"
      CARD = "rounded-2xl border border-stone-200 bg-white shadow-sm"

      private

      def icon(name)
        raw(safe(view_context.lucide_icon(name, :class => "size-5", "aria-hidden" => "true")))
      end

      def page(title, active: :people)
        doctype
        html(lang: "en") do
          head do
            meta(charset: "utf-8")
            meta(name: "viewport", content: "width=device-width, initial-scale=1")
            title { "#{title} | The Chapel pastoral workspace" }
            link(rel: "stylesheet", href: view_context.asset_path("tailwind.css"))
            script(type: "module", src: view_context.asset_path("turbo.min.js"))
            script(type: "module", src: view_context.asset_path("workspace.js"))
          end
          body(class: "min-h-screen bg-stone-50 font-sans text-stone-900") do
            header(class: "border-b border-stone-200 bg-white") do
              div(class: "mx-auto flex max-w-7xl flex-wrap items-center " \
                "justify-between gap-4 px-6 py-5") do
                a(href: view_context.dashboard_path,
                  class: "flex items-center gap-3 font-semibold") do
                  span(class: "rounded-xl bg-teal-800 p-2 text-white") { icon("heart-handshake") }
                  div do
                    p(class: "text-xs uppercase tracking-widest text-teal-800") { "The Chapel" }
                    p { "Pastoral workspace" }
                  end
                end
                nav(class: "flex items-center gap-4 text-sm", aria_label: "Workspace views") do
                  {people: ["People", view_context.dashboard_path],
                   map: ["Map", view_context.workspace_map_path],
                   changes: ["Changes", view_context.workspace_changes_path]}.each do |key, values|
                    a(href: values.last, aria_current: (active == key) ? "page" : nil,
                      class: (active == key) ? "font-semibold text-teal-800" : "text-stone-500") do
                      plain values.first
                    end
                  end
                  if view_context.current_user&.administrator?
                    a(href: view_context.admin_root_path, class: "text-stone-500") do
                      plain "Administration"
                    end
                  end
                  post_form(action: view_context.destroy_user_session_path, method: "delete") do
                    button(type: "submit", class: "text-stone-500") { "Sign out" }
                  end
                end
              end
            end
            main(class: "mx-auto max-w-7xl px-6 py-8") do
              if view_context.flash[:notice].present?
                p(role: "status", class: "mb-6 rounded-xl bg-teal-50 p-4 text-teal-900") do
                  plain view_context.flash[:notice]
                end
              end
              if view_context.flash[:alert].present?
                p(role: "alert", class: "mb-6 rounded-xl bg-red-50 p-4 text-red-800") do
                  plain view_context.flash[:alert]
                end
              end
              yield
            end
          end
        end
      end

      def portrait(person_view, size: "size-14")
        person = person_view.person
        div(class: "relative #{size} shrink-0 overflow-hidden " \
          "rounded-full bg-teal-50 text-teal-800") do
          span(class: "flex h-full items-center justify-center font-semibold") { person.initials }
          if person_view.photo?
            img(src: view_context.workspace_person_photo_path(person), alt: "",
              loading: "lazy", data_portrait: true,
              class: "absolute inset-0 h-full w-full object-cover")
          end
        end
      end

      def post_form(action:, method: "post")
        form(action: action, method: "post") do
          input(type: "hidden", name: "authenticity_token",
            value: view_context.form_authenticity_token)
          input(type: "hidden", name: "_method", value: method) unless method == "post"
          yield
        end
      end
    end
  end
end
