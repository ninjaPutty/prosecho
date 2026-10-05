class AccessPreview < Lookbook::Preview
  def sign_in
    render Components::SignIn.new
  end

  def sign_in_error
    render Components::SignIn.new(message: "Invalid email or password.")
  end
end
