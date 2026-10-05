require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "passwords use Argon2id and verify through Devise" do
    user = User.create!(email: "new@example.test", password: "valid8pw")
    assert_match(/\A\$argon2id\$/, user.encrypted_password)
    assert user.valid_password?("valid8pw")
    assert_not user.valid_password?("incorrect password")
    assert_not user.encrypted_password.include?("valid8pw")
  end

  test "disabled users cannot authenticate and password changes invalidate sessions" do
    user = users(:staff)
    before = user.authenticatable_salt
    user.update!(password: "a changed long passphrase")
    assert_not_equal before, user.authenticatable_salt
    user.update!(active: false)
    assert_not user.active_for_authentication?
  end

  test "invalid hashes and short passwords do not become valid credentials" do
    user = User.new(email: "invalid@example.test", password: "short7p")
    assert_not user.valid?
    user.encrypted_password = "$argon2id$invalid"
    assert_not user.valid_password?("some passphrase")
  end

  test "administrator status alone grants no pastoral data access" do
    user = users(:administrator)
    assert user.administrator?
    assert_empty user.campus_accesses
    assert_not user.can_access?(campuses(:north).id, :directory)
  end

  test "campus grants and sensitive permissions are independent and deny by default" do
    user = users(:staff)
    assert user.can_access?(campuses(:north).id, :directory)
    assert user.can_access?(campuses(:north).id, :photos)
    assert_not user.can_access?(campuses(:north).id, :history)
    assert_not user.can_access?(campuses(:north).id, :locations)
    assert_not user.can_access?(campuses(:south).id, :directory)
    assert_not user.can_access?(nil, :directory)
    assert_not user.can_access?(campuses(:north).id, :unknown)
    user.update!(active: false)
    assert_not user.can_access?(campuses(:north).id, :directory)
  end
end
