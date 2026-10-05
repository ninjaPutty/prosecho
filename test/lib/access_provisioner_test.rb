require "test_helper"

class AccessProvisionerTest < ActiveSupport::TestCase
  test "only active administrators may provision or grant staff access" do
    service = Access::Provisioner.new(actor: users(:staff))
    assert_no_difference "User.count" do
      assert_raises(Access::Provisioner::NotAuthorized) do
        service.provision(email: "another@example.test", password: "another long passphrase")
      end
    end
    assert_raises(Access::Provisioner::NotAuthorized) do
      service.grant(user: users(:staff), campus: campuses(:south))
    end
  end

  test "provision grants no implicit scope and campus grant can be revoked with audit" do
    service = Access::Provisioner.new(actor: users(:administrator))
    user = service.provision(email: "another@example.test", password: "another long passphrase")
    assert_not user.can_access?(campuses(:north).id, :directory)
    assert_difference "AccessEvent.count", 1 do
      service.grant(user: user, campus: campuses(:north))
    end
    assert user.can_access?(campuses(:north).id, :directory)
    service.revoke(user: user, campus: campuses(:north))
    assert_not user.can_access?(campuses(:north).id, :directory)
  end

  test "bootstrap cannot be used to create another administrator" do
    assert_raises(Access::Provisioner::NotAuthorized) do
      Access::Provisioner.bootstrap(email: "extra@example.test", password: "another long passphrase")
    end
  end

  test "bootstrap provisions only an administrator and records the actor" do
    CampusAccess.delete_all
    User.delete_all
    user = Access::Provisioner.bootstrap(email: "first@example.test",
      password: "a unique administrator passphrase")
    assert user.administrator?
    assert_empty user.campuses
    event = AccessEvent.find_by!(resource_id: user.id)
    assert_equal user.id, event.actor_id
    assert_equal "provisioned", event.outcome
  end

  test "administrator updates sensitive permissions explicitly" do
    service = Access::Provisioner.new(actor: users(:administrator))
    service.update(user: users(:staff), attributes: {view_history: true})
    assert users(:staff).can_access?(campuses(:north).id, :history)
    assert_raises(ArgumentError) do
      service.update(user: users(:staff), attributes: {encrypted_password: "bad"})
    end
  end
end
