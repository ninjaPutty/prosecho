require "test_helper"

class DataPolicyTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "administrator can save a partial draft and return to it" do
    sign_in users(:administrator)
    get admin_data_policy_path
    assert_response :success
    assert_select "h1", "Data decisions"
    assert_select "textarea[name='data_policy[address_source]']", text: /PrimaryFamilyId/
    revision = policy_revision
    assert_difference "DataPolicy.count", 1 do
      patch admin_data_policy_path, params: {data_policy: {
        revision: revision, history_retention_days: 90, status: "draft"
      }}
    end
    assert_redirected_to admin_data_policy_path
    get admin_data_policy_path
    assert_select "input[name='data_policy[history_retention_days]'][value='90']"
    policy = DataPolicy.current
    assert_equal users(:administrator).id, policy.recorded_by_id
    assert_not policy.confirmed?
    assert_nil policy.confirmed_at
  end

  test "complete agreed decisions persist the allowlist reviewer and readiness" do
    sign_in users(:administrator)
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    get admin_data_policy_path
    token = css_select("form[action='#{admin_data_policy_path}'] " \
      "input[name='authenticity_token']").first["value"]
    revision = policy_revision
    assert_difference "DataPolicy.count", 1 do
      patch admin_data_policy_path, params: {
        authenticity_token: token,
        data_policy: complete_decisions.merge(revision: revision,
          recorded_by_id: users(:staff).id, confirmed_at: "2000-01-01")
      }
    end
    assert_redirected_to admin_data_policy_path
    policy = DataPolicy.current
    assert policy.confirmed?
    assert_equal users(:administrator).id, policy.confirmed_by_id
    assert policy.confirmed_at > 1.minute.ago
    assert_equal ["FirstVisit", "Essentials"], policy.attribute_keys
    assert_equal ["first_name", "last_name", "primary_campus"], policy.selected_fields
    settings = Pastoral::Configuration.load(environment: {"ROCK_API_KEY" => "synthetic-test-key"})
    assert_empty settings.data_blockers
    assert settings.directory_ready?
    assert_not settings.map_ready?
    assert_not settings.live_sync_enabled?
    assert AccessEvent.exists?(resource: "data_policy", resource_id: policy.id, outcome: "updated")
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  test "invalid retention and unsupported fields cannot confirm or replace decisions" do
    sign_in users(:administrator)
    get admin_data_policy_path
    assert_no_difference "DataPolicy.count" do
      decisions = complete_decisions.merge(revision: policy_revision,
        history_retention_days: -5, selected_fields: ["giving_data"])
      patch admin_data_policy_path, params: {data_policy: decisions}
    end
    assert_response :unprocessable_content
    assert_select "[role='alert']", text: /Please check these details/
    assert_empty Pastoral::Configuration.load(environment: {}).data_decisions["attribute_keys"]
  end

  test "stale edits cannot overwrite another administrators saved revision" do
    sign_in users(:administrator)
    get admin_data_policy_path
    stale = policy_revision
    patch admin_data_policy_path, params: {data_policy: {
      revision: stale, status: "draft", history_retention_days: 90
    }}
    patch admin_data_policy_path, params: {data_policy: {
      revision: stale, status: "draft", history_retention_days: 365
    }}
    assert_response :conflict
    assert_equal 90, DataPolicy.current.history_retention_days
    assert_select "[role='alert']", text: /Another administrator changed these decisions/
  end

  test "reverting to a draft clears confirmation and blocks readiness" do
    sign_in users(:administrator)
    get admin_data_policy_path
    decisions = complete_decisions.merge(revision: policy_revision)
    patch admin_data_policy_path, params: {data_policy: decisions}
    get admin_data_policy_path
    patch admin_data_policy_path, params: {data_policy: {
      revision: policy_revision, status: "draft"
    }}
    policy = DataPolicy.current
    assert_not policy.confirmed?
    assert_nil policy.confirmed_by_id
    assert_nil policy.confirmed_at
    assert_includes Pastoral::Configuration.load(environment: {}).data_blockers,
      "Data decisions have not been approved"
  end

  test "policy is administrator-only and rejects unverified requests" do
    get admin_data_policy_path
    assert_redirected_to new_user_session_path
    sign_in users(:staff)
    get admin_data_policy_path
    assert_response :forbidden
    assert_no_difference "DataPolicy.count" do
      patch admin_data_policy_path, params: {data_policy: complete_decisions.merge(revision: "new")}
    end
    assert_response :forbidden
    sign_in users(:administrator)
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    assert_no_difference "DataPolicy.count" do
      patch admin_data_policy_path, params: {data_policy: complete_decisions.merge(revision: "new")}
    end
    assert_response :unprocessable_content
  ensure
    ActionController::Base.allow_forgery_protection = original unless original.nil?
  end

  private

  def complete_decisions
    {
      address_handling: "Omit missing or ambiguous home addresses until reviewed.",
      address_source: "PrimaryFamilyId -> Home GroupLocation -> Location",
      attribute_keys_text: "FirstVisit\nEssentials\nFirstVisit",
      backup_retention_days: 30,
      family_status_meaning: "Engagement category, not marital status.",
      history_retention_days: 365,
      household_handling: "Describe membership changes without guessing life events.",
      household_source: "Active non-archived family members and roles",
      log_retention_days: 90,
      profile_retention_days: 90,
      selected_fields: ["", "first_name", "last_name", "primary_campus"],
      status: "confirmed"
    }
  end

  def policy_revision
    css_select("input[name='data_policy[revision]']").first["value"]
  end
end
