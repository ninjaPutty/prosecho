class LandingPreview < Lookbook::Preview
  layout "component_preview"

  def default
    render Components::Landing.new
  end
end
