require "test_helper"

class HomeTest < ActionDispatch::IntegrationTest
  test "landing page renders without an account" do
    get root_path

    assert_response :success
    assert_select "h1", "Prosecho"
    assert_select "link[rel=stylesheet][href*='tailwind']", count: 1
    assert_select "main[class*='bg-']", count: 1
    assert_select "form[action*='sign_in']", count: 0
  end

  test "inspector is not mounted in test" do
    get "/lookbook"

    assert_response :not_found
  end
end
