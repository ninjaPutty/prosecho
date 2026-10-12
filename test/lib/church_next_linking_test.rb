require "test_helper"
require_relative "../support/directory_policy"

class ChurchNextLinkingTest < ActiveSupport::TestCase
  include DirectoryPolicy

  setup do
    @policy = confirm_directory_policy
    @policy.update!(selected_fields: (@policy.selected_fields + ["email"]).uniq)
    PersonProfile.update_all(policy_revision: @policy.revision)
    @person = person_profiles(:alex)
    @person.update!(first_name: "Alexander", nick_name: "Alex", email: "alex@example.test")
    @admin = users(:administrator)
    CampusAccess.create!(user: @admin, campus: campuses(:north))
  end

  test "fuzzy names handle nicknames accents and minor spelling differences" do
    @person.update!(last_name: "Garcia", display_name: "Alex Garcia")
    account = submit(first_name: "Alex", last_name: "García", email: "new@example.test")
    assert_equal "pending", account.status
    assert_equal @person.id, account.candidates.first.person_profile_id
    account = submit(id: "another", first_name: "Alexandar", last_name: "Garcia",
      email: "another@example.test")
    assert_equal @person.id, account.candidates.first.person_profile_id
    assert_nil @person.reload.churchnext_user_id
  end

  test "unrelated names are not suggested" do
    account = submit(first_name: "Zoe", last_name: "Unrelated", email: "new@example.test")
    assert_empty account.candidates
    assert_equal "pending", account.status
  end

  test "exact non Latin names remain eligible for manual suggestions" do
    @person.update!(first_name: "\u5a1c", last_name: "\u5f20", nick_name: nil)
    account = submit(first_name: "\u5a1c", last_name: "\u5f20", email: "new@example.test")
    assert_equal @person.id, account.candidates.first.person_profile_id
    assert_equal 100, account.candidates.first.score
    assert_equal "pending", account.status
  end

  test "one-to-one linking cannot overwrite a person's existing ChurchNext identity" do
    first = submit
    assert_equal "linked", first.status
    second = submit(id: "another")
    assert_equal "pending", second.status
    candidate = second.candidates.find_by!(person_profile: @person)
    assert_raises(ChurchNext::Linker::Conflict) do
      ChurchNext::Linker.new.match!(candidate: candidate, actor: @admin)
    end
    assert_equal first.external_user_id, @person.reload.churchnext_user_id
    assert_equal 1, ChurchNextLinkDelivery.count
  end

  test "refreshes preserve ChurchNext links and remove unapproved emails" do
    submit
    assert_equal "cn-101", @person.reload.churchnext_user_id
    @policy.update!(selected_fields: @policy.selected_fields - ["email"])
    assert_raises(ChurchNext::Linker::NotReady) { submit(id: "another") }
  end

  test "decided pairs survive person deletion and reimport" do
    account = submit(email: "new@example.test")
    candidate = account.candidates.find_by!(person_profile: @person)
    ChurchNext::Linker.new.reject!(candidate: candidate, actor: @admin)
    attributes = @person.attributes.except("id", "created_at", "updated_at")
    @person.destroy!
    replacement = PersonProfile.create!(attributes)
    submit(email: "new@example.test")
    assert_equal "rejected", candidate.reload.status
    assert_nil replacement.churchnext_user_id
  end

  test "established links reserve the Rock identity even if its local projection is removed" do
    original = submit
    attributes = @person.attributes.except("id", "created_at", "updated_at", "churchnext_user_id")
    @person.destroy!
    replacement = PersonProfile.create!(attributes)
    another = submit(id: "another")
    assert_equal "pending", another.status
    assert_nil replacement.reload.churchnext_user_id
    candidate = another.candidates.find_by!(person_profile: replacement)
    assert_raises(ChurchNext::Linker::Conflict) do
      ChurchNext::Linker.new.match!(candidate: candidate, actor: @admin)
    end
    assert_equal "linked", original.reload.status
    assert_nil original.person_profile_id
  end

  test "manual decisions reload the actor's current role" do
    account = submit(email: "new@example.test")
    candidate = account.candidates.find_by!(person_profile: @person)
    User.where(id: @admin.id).update_all(role: "staff")
    assert_raises(ActiveRecord::RecordNotFound) do
      ChurchNext::Linker.new.match!(candidate: candidate, actor: @admin)
    end
    assert_nil @person.reload.churchnext_user_id
  end

  test "intake and fuzzy search logging redact names emails and external account IDs" do
    output = StringIO.new
    original_logger = ActiveRecord::Base.logger
    ActiveRecord::Base.logger = ActiveSupport::Logger.new(output)
    account = submit(id: "synthetic-private-user-id", first_name: "PrivateGivenName",
      last_name: "PrivateFamilyName", email: "synthetic-private-email@example.test")
    [account.first_name, account.last_name, account.email, account.external_user_id].each do |value|
      assert_not_includes output.string, value
      assert_not_includes account.inspect, value
    end
  ensure
    ActiveRecord::Base.logger = original_logger
  end

  private

  def submit(id: "cn-101", first_name: "Alex", last_name: "Example", email: "alex@example.test")
    ChurchNext::Linker.new.submit!(external_user_id: id, first_name: first_name,
      last_name: last_name, email: email, email_verified: true, photo_available: false)
  end
end
