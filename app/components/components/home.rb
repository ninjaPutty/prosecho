module Components
  class Home < Phlex::HTML
    def view_template
      doctype
      html(lang: "en") do
        head do
          meta(charset: "utf-8")
          meta(name: "viewport", content: "width=device-width, initial-scale=1")
          title { "Prosecho" }
          link(rel: "stylesheet", href: view_context.asset_path("tailwind.css"))
        end
        body do
          render Components::Landing.new
        end
      end
    end
  end
end
