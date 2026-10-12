class ChurchNextAccountsPreview < Lookbook::Preview
  Query = Struct.new(:accounts, :candidates, :page, :total, :policy) do
    def ready?
      true
    end
  end

  def empty
    render Components::Workspace::ChurchNextAccounts.new(query: query([], {}), actor: actor)
  end

  def linked
    account = sample_account
    account.status = "linked"
    account.define_singleton_method(:link_delivery) { nil }
    render Components::Workspace::ChurchNextAccounts.new(query: query([account], {}), actor: actor)
  end

  def pending
    account = sample_account
    person = PersonProfile.new(id: "00000000-0000-4000-8000-000000000102",
      first_name: "Alex", last_name: "Example", display_name: "Alex Example",
      email: "directory@example.test")
    candidate = ChurchNextCandidate.new(id: "00000000-0000-4000-8000-000000000103",
      person_profile: person, score: 94, reason: "name")
    render Components::Workspace::ChurchNextAccounts.new(
      query: query([account], {account.id => [candidate]}), actor: actor
    )
  end

  private

  def actor
    User.new(role: "administrator", view_photos: false)
  end

  def query(accounts, candidates)
    Query.new(accounts, candidates, 1, accounts.length,
      DataPolicy.new(selected_fields: DataPolicy::FIELD_LABELS.keys))
  end

  def sample_account
    ChurchNextAccount.new(id: "00000000-0000-4000-8000-000000000101", external_user_id: "synthetic-101",
      first_name: "Alex", last_name: "Example", email: "church-next@example.test",
      email_verified: true, status: "pending", photo_available: false)
  end
end
