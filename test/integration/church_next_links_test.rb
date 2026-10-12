require "test_helper"
require "minitest/mock"
require_relative "../support/directory_policy"

class ChurchNextLinksTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include DirectoryPolicy

  setup do
    @old_token = ENV["CHURCHNEXT_API_TOKEN"]
    ENV["CHURCHNEXT_API_TOKEN"] = "synthetic-integration-token-for-tests-only"
    @policy = confirm_directory_policy
    @policy.update!(selected_fields: (@policy.selected_fields + ["email"]).uniq)
    PersonProfile.update_all(policy_revision: @policy.revision)
    @person = person_profiles(:alex)
    @person.update!(email: "alex@example.test")
    @admin = users(:administrator)
    CampusAccess.create!(user: @admin, campus: campuses(:north))
  end

  teardown do
    ENV["CHURCHNEXT_API_TOKEN"] = @old_token
  end

  test "API authenticates independently of staff sessions and is private" do
    sign_in @admin
    post api_v1_church_next_links_path, params: submission, as: :json
    assert_response :unauthorized
    assert_equal 0, ChurchNextAccount.count
    submit
    assert_response :success
    assert_equal true, response.parsed_body["linked"]
    assert_includes response.headers["Cache-Control"], "no-store"
    assert_not_includes response.body, @person.display_name
    assert_not_includes response.body, @person.email
    assert_equal "cn-101", @person.reload.churchnext_user_id
  end

  test "email linking is idempotent and creates one durable notification" do
    assert_difference "ChurchNextLinkDelivery.count", 1 do
      submit
      assert_response :success
      submit
      assert_response :success
    end
    assert_equal 1, ChurchNextAccount.count
    assert_equal "linked", ChurchNextAccount.find_by!(external_user_id: "cn-101").status
    assert_equal 1, ChurchNextLinkDelivery.where(status: "pending").count
  end

  test "ambiguous or unverified emails go to review without linking" do
    person_profiles(:casey).update!(email: @person.email)
    submit
    assert_response :accepted
    assert_equal false, response.parsed_body["linked"]
    assert_nil @person.reload.churchnext_user_id
    assert_equal 2, ChurchNextCandidate.count
    submit(external_user_id: "cn-102", email_verified: false)
    assert_response :accepted
    assert_equal 0, ChurchNextLinkDelivery.count
  end

  test "manual review respects role campus photos and CSRF" do
    submit(email: "different@example.test")
    account = ChurchNextAccount.find_by!(external_user_id: "cn-101")
    candidate = account.candidates.find_by!(person_profile: @person)
    sign_in users(:staff)
    get admin_church_next_accounts_path
    assert_response :forbidden
    sign_in @admin
    get admin_church_next_accounts_path
    assert_response :success
    assert_includes response.body, "different@example.test"
    assert_includes response.body, @person.display_name
    assert_includes response.body, @person.email
    assert_select "img[src=?]", workspace_person_photo_path(@person), count: 0
    @admin.update!(view_photos: true)
    get admin_church_next_accounts_path
    assert_select "img[src=?]", workspace_person_photo_path(@person), count: 1
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    post match_admin_church_next_candidate_path(candidate)
    assert_response :unprocessable_content
    assert_nil @person.reload.churchnext_user_id
    ActionController::Base.allow_forgery_protection = original
    post match_admin_church_next_candidate_path(candidate)
    assert_redirected_to admin_church_next_accounts_path
    assert_equal account.external_user_id, @person.reload.churchnext_user_id
    assert_equal 1, ChurchNextLinkDelivery.count
  ensure
    ActionController::Base.allow_forgery_protection = original unless original.nil?
  end

  test "guessed and revoked campus candidates cannot be approved" do
    submit(email: "different@example.test")
    candidate = ChurchNextCandidate.find_by!(person_profile: @person)
    sign_in @admin
    @admin.campus_accesses.delete_all
    get admin_church_next_accounts_path
    assert_response :success
    assert_not_includes response.body, @person.email
    post match_admin_church_next_candidate_path(candidate)
    assert_response :not_found
    assert_nil @person.reload.churchnext_user_id
  end

  test "rejections survive repeat requests and later matching emails" do
    submit(email: "different@example.test")
    candidate = ChurchNextCandidate.find_by!(person_profile: @person)
    sign_in @admin
    post reject_admin_church_next_candidate_path(candidate)
    assert_redirected_to admin_church_next_accounts_path
    submit
    assert_response :accepted
    assert_nil @person.reload.churchnext_user_id
    assert_equal "rejected", candidate.reload.status
    assert_equal @admin.id, candidate.reviewed_by_id
  end

  test "missing configuration invalid payload and unapproved email fail closed" do
    ENV.delete("CHURCHNEXT_API_TOKEN")
    submit
    assert_response :service_unavailable
    ENV["CHURCHNEXT_API_TOKEN"] = "synthetic-integration-token-for-tests-only"
    submit(first_name: "x" * 201)
    assert_response :unprocessable_content
    submit(email_verified: "true")
    assert_response :unprocessable_content
    @policy.update!(selected_fields: @policy.selected_fields - ["email"])
    submit
    assert_response :service_unavailable
    assert_equal 0, ChurchNextAccount.count
  end

  test "API rejects oversized requests and rate limits before authentication" do
    post api_v1_church_next_links_path, params: {extra: "x" * 17000}, as: :json,
      headers: {"Authorization" => "Bearer synthetic-integration-token-for-tests-only"}
    assert_response :content_too_large
    Api::V1::ChurchNextLinksController.cache_store.stub(:increment, 61) do
      submit
      assert_response :too_many_requests
    end
    assert_equal 0, ChurchNextAccount.count
  end

  test "ChurchNext photos require administrator photo permission and never expose the origin" do
    submit(email: "different@example.test", photo_available: true)
    account = ChurchNextAccount.find_by!(external_user_id: "cn-101")
    sign_in @admin
    get photo_admin_church_next_account_path(account)
    assert_response :forbidden
    @admin.update!(view_photos: true)
    image = Integrations::ChurchNext::Client::Photo.new(body: "synthetic-image".b, content_type: "image/png")
    client = Object.new
    client.define_singleton_method(:photo) { |_id| image }
    Integrations::ChurchNext::Client.stub(:new, client) do
      get photo_admin_church_next_account_path(account)
    end
    assert_response :success
    assert_equal "image/png", response.media_type
    assert_includes response.headers["Cache-Control"], "no-store"
    sign_in users(:staff)
    get photo_admin_church_next_account_path(account)
    assert_response :forbidden
  end

  test "wrong bearer credentials do not create identities or suggestions" do
    post api_v1_church_next_links_path, params: submission, as: :json,
      headers: {"Authorization" => "Bearer wrong-synthetic-token"}
    assert_response :unauthorized
    assert_equal 0, ChurchNextAccount.count
    assert_equal 0, ChurchNextCandidate.count
  end

  private

  def submission(external_user_id: "cn-101", first_name: "Alex", last_name: "Example",
    email: "alex@example.test", email_verified: true, photo_available: false)
    {church_next_user_id: external_user_id, first_name: first_name, last_name: last_name,
     email: email, email_verified: email_verified, photo_available: photo_available}
  end

  def submit(**values)
    post api_v1_church_next_links_path, params: submission(**values), as: :json,
      headers: {"Authorization" => "Bearer synthetic-integration-token-for-tests-only"}
  end
end
