require "test_helper"

class AdminDashboardTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "first visit offers setup and creates exactly one administrator" do
    CampusAccess.delete_all
    User.delete_all
    get admin_root_path
    assert_response :success
    assert_select "h1", "Set up Prosecho"
    assert_select "input[name='user[password_confirmation]']"
    assert_difference "User.count", 1 do
      post admin_setup_path, params: {user: {
        email: "first@example.test",
        password: "a unique first passphrase", password_confirmation: "a unique first passphrase",
        role: "staff", campus_ids: [campuses(:north).id]
      }}
    end
    assert_redirected_to admin_root_path
    user = User.find_by!(email: "first@example.test")
    assert user.administrator?
    assert_empty user.campuses
    follow_redirect!
    assert_select "h1", "Account administration"
    assert_no_difference "User.count" do
      post admin_setup_path, params: {user: {
        email: "second@example.test",
        password: "a second long passphrase", password_confirmation: "a second long passphrase"
      }}
    end
    assert_response :conflict
  end

  test "invalid setup remains available and creates no account" do
    CampusAccess.delete_all
    User.delete_all
    assert_no_difference "User.count" do
      post admin_setup_path, params: {user: {
        email: "first@example.test", password: "short", password_confirmation: "different"
      }}
    end
    assert_response :unprocessable_content
    assert_select "input[type='password'][value]", count: 0
    get admin_root_path
    assert_response :success
  end

  test "after setup all administration routes require administrator access" do
    get admin_root_path
    assert_redirected_to new_user_session_path
    sign_in users(:staff)
    get admin_root_path
    assert_response :forbidden
    assert_no_difference "User.count" do
      post admin_accounts_path, params: {user: {
        email: "attack@example.test", password: "a sufficiently long password",
        role: "administrator"
      }}
    end
    assert_response :forbidden
    assert_no_difference "Campus.count" do
      post import_admin_campuses_path
    end
    assert_response :forbidden
  end

  test "administrator creates edits and deactivates accounts with explicit campus grants" do
    sign_in users(:administrator)
    get new_admin_account_path
    assert_response :success
    post admin_accounts_path, params: {user: {
      email: "created@example.test", active: "1",
      password: "a unique long passphrase", password_confirmation: "a unique long passphrase",
      role: "staff", view_photos: "1", campus_ids: ["", campuses(:north).id]
    }}
    user = User.find_by!(email: "created@example.test")
    assert_redirected_to admin_root_path
    assert user.can_access?(campuses(:north).id, :photos)
    assert_not user.can_access?(campuses(:south).id, :directory)
    get edit_admin_account_path(user)
    assert_response :success
    assert_select "input[type='password'][value]", count: 0
    hash = user.encrypted_password
    patch admin_account_path(user), params: {user: {
      email: "edited@example.test", active: "0",
      role: "staff", view_photos: "0", password: "", password_confirmation: "", campus_ids: [""]
    }}
    assert_redirected_to admin_root_path
    user.reload
    assert_not user.active?
    assert_empty user.campuses
    assert_equal hash, user.encrypted_password
    assert_equal "edited@example.test", user.email
  end

  test "invalid account changes roll back grants and protect the final administrator" do
    sign_in users(:administrator)
    staff = users(:staff)
    patch admin_account_path(staff), params: {user: {
      email: "invalid email", campus_ids: [campuses(:south).id]
    }}
    assert_response :unprocessable_content
    assert_equal [campuses(:north).id], staff.reload.campus_ids
    patch admin_account_path(users(:administrator)), params: {user: {role: "staff"}}
    assert_response :unprocessable_content
    assert users(:administrator).reload.administrator?
    assert_includes response.body, "last active administrator"
    patch admin_account_path(users(:administrator)), params: {user: {active: "0"}}
    assert_response :unprocessable_content
    assert users(:administrator).reload.active?
  end

  test "invalid campus grants cannot persist a newly created account" do
    sign_in users(:administrator)
    assert_no_difference "User.count" do
      post admin_accounts_path, params: {user: {
        email: "invalid-grant@example.test", password: "a unique long passphrase",
        password_confirmation: "a unique long passphrase", campus_ids: ["-" * 36]
      }}
    end
    assert_response :unprocessable_content
  end

  test "campus hierarchy is editable without changing Rock and does not inherit access" do
    sign_in users(:administrator)
    campus = Campus.create!(name: "Example Satellite", rock_id: 100003,
      parent_id: campuses(:north).id, active: true)
    assert_equal campuses(:north), campus.parent
    assert_not users(:staff).can_access?(campus.id, :directory)
    patch admin_campus_path(campuses(:north)), params: {campus: {
      name: "Renamed North", parent_id: campus.id
    }}
    assert_response :unprocessable_content
    assert_nil campuses(:north).reload.parent_id
    patch admin_campus_path(campuses(:north)), params: {campus: {active: "0"}}
    assert_redirected_to admin_root_path
    assert_not users(:staff).can_access?(campuses(:north).id, :directory)
  end

  test "administration mutations are CSRF protected" do
    sign_in users(:administrator)
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    post import_admin_campuses_path
    assert_response :unprocessable_content
  ensure
    ActionController::Base.allow_forgery_protection = original
  end
end
