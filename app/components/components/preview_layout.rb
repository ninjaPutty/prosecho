module Components
  class PreviewLayout < Phlex::HTML
    include Phlex::Rails::Layout

    def view_template
      doctype
      html(lang: "en") do
        head do
          meta(charset: "utf-8")
          meta(name: "viewport", content: "width=device-width, initial-scale=1")
          title { "Prosecho preview" }
          link(rel: "stylesheet", href: view_context.asset_path("tailwind.css"))
        end
        body { yield }
      end
    end
  end
end
