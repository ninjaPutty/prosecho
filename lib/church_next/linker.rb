module ChurchNext
  class Linker
    class Conflict < StandardError; end
    class Invalid < StandardError; end
    class NotReady < StandardError; end

    def match!(candidate:, actor:)
      synchronize do
        actor.reload
        candidate = ChurchNextCandidate.visible_to(actor).lock.find(candidate.id)
        account, person = candidate.church_next_account, candidate.person_profile
        return account if candidate.status == "matched" && account.linked?
        raise Conflict, "This suggestion has already been decided." unless candidate.status == "pending"
        link!(account, person)
        candidate.update!(status: "matched", reviewed_by: actor, decided_at: Time.current)
        AccessEvent.create!(actor: actor, resource: "church_next_accounts", resource_id: account.id,
          outcome: "updated")
        account
      end
    end

    def reject!(candidate:, actor:)
      synchronize do
        actor.reload
        candidate = ChurchNextCandidate.visible_to(actor).lock.find(candidate.id)
        raise Conflict, "This account has already been linked." if candidate.church_next_account.linked?
        candidate.update!(status: "rejected", reviewed_by: actor, decided_at: Time.current)
        AccessEvent.create!(actor: actor, resource: "church_next_accounts",
          resource_id: candidate.church_next_account_id, outcome: "updated")
      end
    end

    def submit!(external_user_id:, first_name:, last_name:, email:, email_verified:, photo_available: false)
      strings = [external_user_id, first_name, last_name, email]
      unless strings.all? { |value| value.is_a?(String) } &&
          [true, false].include?(email_verified) && [true, false].include?(photo_available)
        raise Invalid, "Invalid account fields."
      end
      normalized_email = Directory::EmailAddress.normalize(email)
      raise Invalid, "A valid email address is required." unless normalized_email

      synchronize do
        policy = DataPolicy.current
        unless policy.persisted? && policy.confirmed? && policy.valid? &&
            policy.selected_fields.include?("email")
          raise NotReady, "Approve email in Data decisions and refresh the directory first."
        end
        account = ChurchNextAccount.find_or_initialize_by(external_user_id: external_user_id)
        return account if account.linked?

        account.update!(first_name: first_name.strip, last_name: last_name.strip,
          email: normalized_email, email_verified: email_verified, photo_available: photo_available)
        scope = PersonProfile.where(policy_revision: policy.revision, in_population: true,
          source_system: "rock.chapel.org", campus_id: Campus.active.select(:id))
        rejected = account.candidates.where(status: "rejected").pluck(:rock_guid)
        emails = scope.where(email: normalized_email).order(:id).limit(21).to_a
        # Shared household emails must never pick an arbitrary person. Remembered
        # rejections also override future exact-email automatic linking.
        if email_verified && emails.one? && !rejected.include?(emails.first.rock_guid) &&
            emails.first.churchnext_user_id.nil? && !reserved?(emails.first, account)
          link!(account, emails.first)
        else
          account.candidates.where(status: "pending").delete_all
          proposals = emails.first(20).map { |person| {person: person, score: 100, reason: "email"} }
          proposals += NameMatcher.new.suggestions(account: account, scope: scope)
          proposals.uniq { |entry| entry[:person].rock_guid }.each do |entry|
            person = entry[:person]
            next if rejected.include?(person.rock_guid)
            account.candidates.create!(person_profile: person, rock_guid: person.rock_guid,
              policy_revision: policy.revision, score: entry[:score], reason: entry[:reason])
          end
        end
        account
      end
    rescue ActiveRecord::RecordInvalid
      raise Invalid, "Invalid account fields."
    end

    private

    def link!(account, person)
      raise Conflict, "This account has already been linked." if account.linked?
      if reserved?(person, account)
        raise Conflict, "This person is already linked to another ChurchNext account."
      end
      decision = account.candidates.find_or_initialize_by(rock_guid: person.rock_guid)
      raise Conflict, "This pair was previously rejected." if decision.status == "rejected"
      if decision.new_record?
        decision.assign_attributes(score: 100, reason: "email", policy_revision: person.policy_revision)
      end
      decision.update!(person_profile: person, status: "matched", decided_at: Time.current)
      person.update!(churchnext_user_id: account.external_user_id)
      account.update!(status: "linked", person_profile: person, linked_at: Time.current)
      # The outbox commits with the link. Scheduled delivery can recover a worker
      # crash or enqueue failure without losing the ChurchNext notification.
      account.create_link_delivery!(prosecho_person_id: person.id)
    end

    def reserved?(person, account)
      (person.churchnext_user_id.present? && person.churchnext_user_id != account.external_user_id) ||
        ChurchNextCandidate.where(rock_guid: person.rock_guid, status: "matched")
          .where.not(church_next_account_id: account.id).exists?
    end

    def synchronize
      PersonProfile.transaction do
        # Share the publication lock so a campus/policy refresh cannot race a link.
        PersonProfile.connection.execute("SELECT pg_advisory_xact_lock(73005000)")
        yield
      end
    end
  end
end
