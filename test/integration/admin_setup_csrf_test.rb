require "test_helper"

class AdminSetupCsrfTest < ActionDispatch::IntegrationTest
  setup do
    @forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    CampusAccess.delete_all
    User.delete_all
    host! "localhost:3100"
  end

  teardown do
    ActionController::Base.allow_forgery_protection = @forgery_protection
  end

  test "browser setup submits the rendered token with its session and signs in" do
    get admin_root_path
    assert_response :success
    token = setup_token
    assert cookies["_prosecho_session"].present?
    assert_difference "User.count", 1 do
      post admin_setup_path, params: valid_setup.merge(authenticity_token: token),
        headers: {"Origin" => "http://localhost:3100"}
    end
    assert_redirected_to admin_root_path
    follow_redirect!
    assert_response :success
    assert_select "h1", "Account administration"
    assert User.find_by!(email: "csrf-admin@example.test").administrator?
  end

  test "stale session renders a fresh setup form without creating an account" do
    get admin_root_path
    stale_token = setup_token
    cookies.delete("_prosecho_session")
    assert_no_difference "User.count" do
      post admin_setup_path, params: valid_setup.merge(authenticity_token: stale_token),
        headers: {"Origin" => "http://localhost:3100"}
    end
    assert_response :unprocessable_content
    assert_select "h1", "Set up Prosecho"
    assert_select "[role='alert']", text: /setup session expired or changed/
    assert_select "input[type='password'][value]", count: 0
    token = setup_token
    assert_not_equal stale_token, token
    assert_difference "User.count", 1 do
      post admin_setup_path, params: valid_setup.merge(authenticity_token: token),
        headers: {"Origin" => "http://localhost:3100"}
    end
    assert_redirected_to admin_root_path
  end

  test "unverified submissions never reopen setup after an administrator exists" do
    get admin_root_path
    Access::Provisioner.bootstrap(email: "already@example.test", password: "a long new passphrase")
    assert_no_difference "User.count" do
      post admin_setup_path, params: valid_setup, headers: {"Origin" => "http://localhost:3100"}
    end
    assert_response :conflict
    assert_select "form[action=?]", admin_setup_path, count: 0
  end

  private

  def setup_token
    input = css_select("form[action='#{admin_setup_path}'] input[name='authenticity_token']").first
    assert input, "Setup form must render an authenticity token"
    input["value"]
  end

  def valid_setup
    {user: {email: "csrf-admin@example.test", password: "a unique administrator passphrase",
            password_confirmation: "a unique administrator passphrase"}}
  end
end
