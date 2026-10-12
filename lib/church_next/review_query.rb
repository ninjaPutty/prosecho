module ChurchNext
  class ReviewQuery
    PAGE_SIZE = 20
    attr_reader :accounts, :actor, :candidates, :page, :policy, :total

    def initialize(actor:, page: 1)
      @actor, @policy = actor, DataPolicy.current
      @page = page.to_i.clamp(1, 10000)
      allowed = actor.administrator? && actor.active? && !actor.access_locked?
      scope = allowed ? ChurchNextAccount.all : ChurchNextAccount.none
      @total = scope.count
      @accounts = scope.includes(:link_delivery).order(created_at: :desc, id: :desc)
        .limit(PAGE_SIZE).offset((@page - 1) * PAGE_SIZE).to_a
      @candidates = ChurchNextCandidate.visible_to(actor, policy: policy)
        .where(church_next_account_id: @accounts.map(&:id), status: "pending")
        .includes(:person_profile).order(score: :desc, id: :asc).group_by(&:church_next_account_id)
    end

    def ready?
      policy.persisted? && policy.confirmed? && policy.valid? && policy.selected_fields.include?("email")
    end
  end
end
