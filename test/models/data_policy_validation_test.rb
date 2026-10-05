require "test_helper"

class DataPolicyValidationTest < ActiveSupport::TestCase
  test "drafts accept missing decisions but not invalid retention or custom keys" do
    policy = DataPolicy.new(DataPolicy.default_attributes.merge(recorded_by: users(:administrator)))
    assert policy.valid?
    policy.history_retention_days = "1.5"
    assert_not policy.valid?
    policy.history_retention_days = nil
    policy.attribute_keys_text = "invalid key"
    assert_not policy.valid?
    assert policy.errors[:attribute_keys].present?
  end

  test "confirmation requires complete rules retention and attribution" do
    attributes = DataPolicy.default_attributes.merge(
      recorded_by: users(:administrator), status: "confirmed"
    )
    policy = DataPolicy.new(attributes)
    assert_not policy.valid?
    assert policy.errors[:address_handling].present?
    assert policy.errors[:history_retention_days].present?
    assert policy.errors[:confirmed_by].present?
  end

  test "the singleton database constraint prevents multiple active policy records" do
    attributes = DataPolicy.default_attributes.merge(recorded_by: users(:administrator))
    DataPolicy.create!(attributes)
    duplicate = DataPolicy.new(attributes)
    assert_raises(ActiveRecord::RecordNotUnique) do
      DataPolicy.transaction(requires_new: true) { duplicate.save! }
    end
  end
end
