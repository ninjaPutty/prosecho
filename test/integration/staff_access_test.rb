require "test_helper"

class StaffAccessTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "anonymous users must sign in to view the staff dashboard" do
    get dashboard_path
    assert_redirected_to new_user_session_path
    get new_user_session_path
    assert_response :success
    assert_select "form[action=?]", user_session_path
    assert_select "input[name='user[password]'][type='password']"
    assert_select "input[name='authenticity_token']"
  end

  test "sign in and sign out work without public registration" do
    user = users(:staff)
    user.update!(password: "a unique long passphrase")
    post user_session_path, params: {user: {email: user.email, password: "a unique long passphrase"}}
    assert_redirected_to dashboard_path
    get dashboard_path
    assert_response :success
    assert_includes response.headers["Cache-Control"], "no-store"
    delete destroy_user_session_path
    assert_redirected_to root_path
    get dashboard_path
    assert_redirected_to new_user_session_path
    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path("/users/sign_up")
    end
  end

  test "dashboard denies a user with no campus grant and records no personal payload" do
    sign_in users(:administrator)
    assert_difference "AccessEvent.count", 1 do
      get dashboard_path
      assert_response :forbidden
    end
    event = AccessEvent.order(:created_at).last
    assert_equal "dashboard", event.resource
    assert_equal "denied", event.outcome
  end

  test "repeated incorrect passwords lock the account" do
    user = users(:staff)
    user.update!(password: "a unique long passphrase")
    5.times do
      post user_session_path, params: {user: {email: user.email, password: "not the password"}}
    end
    assert user.reload.access_locked?
  end

  test "disabling an account revokes an existing session" do
    user = users(:staff)
    sign_in user
    user.update!(active: false)
    get dashboard_path
    assert_redirected_to new_user_session_path
  end

  test "a password change revokes an existing session" do
    user = users(:staff)
    sign_in user
    get dashboard_path
    assert_response :success
    user.update!(password: "a new longer passphrase")
    get dashboard_path
    assert_redirected_to new_user_session_path
  end

  test "expired sessions require another sign in" do
    sign_in users(:staff)
    get dashboard_path
    assert_response :success
    travel 31.minutes do
      get dashboard_path
      assert_redirected_to new_user_session_path
    end
  end

  test "a campus grant revocation takes effect on the next request" do
    user = users(:staff)
    sign_in user
    user.campus_accesses.destroy_all
    get dashboard_path
    assert_response :forbidden
  end

  test "sign-in rejects a request without a CSRF token when protection is enabled" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    post user_session_path, params: {user: {email: "any@example.test", password: "any password"}}
    assert_response :unprocessable_content
  ensure
    ActionController::Base.allow_forgery_protection = original
  end
end
