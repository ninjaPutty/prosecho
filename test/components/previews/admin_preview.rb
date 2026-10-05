class AdminPreview < Lookbook::Preview
  def data_decisions
    render Components::Admin::DataPolicyForm.new(policy: DataPolicy.new(DataPolicy.default_attributes))
  end

  def empty_dashboard
    render Components::Admin::Dashboard.new(accounts: [], campuses: [])
  end

  def account_form
    render Components::Admin::AccountForm.new(user: User.new,
      campuses: [], new_record: true)
  end

  def first_account_setup
    render Components::Admin::Setup.new(user: User.new)
  end

  def setup_validation_error
    user = User.new(email: "invalid")
    user.errors.add(:email, "is invalid")
    render Components::Admin::Setup.new(user: user)
  end
end
