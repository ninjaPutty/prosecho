class HomeController < ApplicationController
  def index
    render Components::Home.new
  end
end
