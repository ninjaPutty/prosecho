require "test_helper"
require "minitest/mock"

class CampusImportTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "dashboard replaces manual addition with an explicit CSRF-protected fetch action" do
    sign_in users(:administrator)
    get admin_root_path
    assert_response :success
    assert_select "form[action=?]", import_admin_campuses_path do
      assert_select "button", "Fetch campuses from Rock"
      assert_select "input[name='authenticity_token']"
    end
    assert_select "a", text: "Add campus", count: 0
    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path("/admin/campuses/new", method: :get)
    end
  end

  test "administrator can import campuses into the dashboard and repeat without duplicates" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    sign_in users(:administrator)
    get admin_root_path
    token = css_select("form[action='#{import_admin_campuses_path}'] " \
      "input[name='authenticity_token']").first["value"]
    client = Object.new
    client.define_singleton_method(:campuses) do |**_|
      [{"Id" => 100003, "Name" => "Example imported campus", "IsActive" => true}]
    end
    Integrations::Rock::ReadClient.stub(:new, client) do
      assert_difference "Campus.count", 1 do
        post import_admin_campuses_path, params: {authenticity_token: token}
      end
      assert_redirected_to admin_root_path
      follow_redirect!
      assert_includes response.body, "Example imported campus"
      assert_includes response.body, "1 added"
      assert_no_difference "Campus.count" do
        post import_admin_campuses_path, params: {authenticity_token: token}
      end
    end
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  test "connection errors are displayed without partial imports or upstream details" do
    sign_in users(:administrator)
    unavailable = -> { raise Integrations::Rock::ReadClient::ConfigurationError, "missing" }
    Integrations::Rock::ReadClient.stub(:new, unavailable) do
      assert_no_difference "Campus.count" do
        post import_admin_campuses_path
      end
    end
    follow_redirect!
    assert_select "[role='alert']", text: /Rock connection is not configured/
  end

  test "anonymous and staff requests cannot contact Rock" do
    Integrations::Rock::ReadClient.stub(:new, -> { flunk "Must authorize before creating the client" }) do
      post import_admin_campuses_path
      assert_redirected_to new_user_session_path
      sign_in users(:staff)
      post import_admin_campuses_path
      assert_response :forbidden
    end
  end
end
