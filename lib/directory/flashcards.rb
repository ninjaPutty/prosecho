module Directory
  class Flashcards
    class Invalid < StandardError; end

    attr_reader :actor, :policy

    def initialize(actor:, policy: DataPolicy.current)
      @actor, @policy = actor, policy
    end

    def answer!(run:, card:, option_id:)
      # Serialize all practice updates per user, including simultaneous runs.
      actor.with_lock do
        raise Invalid, "This run is unavailable." unless run.user_id == actor.id
        choices = choices_for(run, card)
        return if card.reload.answered_at
        raise Invalid, "Answer the current card first." unless run.next_card == card
        unless choices.any? { |person| person.id == option_id }
          raise Invalid, "Choose one of the four names."
        end
        correct = option_id == card.person_profile_id
        card.update!(answered_at: Time.current, correct: correct)
        review = FlashcardReview.find_or_initialize_by(user: actor, person_profile: card.person_profile)
        review.record_answer!(correct)
      end
    end

    def available
      return PersonProfile.none unless actor.view_photos? && policy.selected_fields.include?("photo")

      PersonProfile.visible_to(actor, policy: policy).where(photo_id: 1..)
        .where.not(display_name: [nil, ""])
        .where("NOT (issues @> ?::jsonb)", '["person_name_missing"]')
    end

    def choices_for(run, card)
      raise Invalid, "This run is unavailable." unless run.user_id == actor.id
      raise Invalid, "This card is unavailable." unless card.flashcard_run_id == run.id

      people = pool(run.campus_ids, run.status_ids).where(id: card.option_ids).to_a
      if people.length != 4 || !people.any? { |person| person.id == card.person_profile_id }
        raise Invalid, "The people or your permissions have changed. Start a new run."
      end
      card.option_ids.map { |id| people.find { |person| person.id == id } }
    end

    def start!(campus_ids:, status_ids:, count:)
      campuses = Array(campus_ids).map(&:to_s).uniq
      statuses = Array(status_ids).map(&:to_s).uniq
      allowed_campuses = actor.campuses.active.pluck(:id)
      allowed_statuses = available.distinct.pluck(:connection_status_id).map { |id| id&.to_s || "unknown" }
      unless campuses.any? && (campuses - allowed_campuses).empty? &&
          statuses.any? && (statuses - allowed_statuses).empty?
        raise Invalid, "Select available campuses and connection statuses."
      end
      unless count.to_s.match?(/\A\d+\z/) && count.to_i.between?(1, 100)
        raise Invalid, "Choose between 1 and 100 people."
      end
      people = pool(campuses, statuses)
      if people.distinct.count(:display_name) < 4
        raise Invalid, "Choose a pool with at least four distinct names and available photos."
      end
      raise Invalid, "Choose no more than #{people.count} people." if count.to_i > people.count

      FlashcardRun.transaction do
        run = FlashcardRun.create!(user: actor, campus_ids: campuses,
          status_ids: statuses, planned_count: count.to_i)
        select_people(people, count.to_i).each_with_index do |person, index|
          options = distractors(people, person) + [person.id]
          run.cards.create!(person_profile: person, option_ids: options.shuffle, position: index + 1)
        end
        run
      end
    end

    def summary
      zone = FlashcardRun.connection.quote(Time.zone.tzinfo.identifier)
      date = Arel.sql("DATE(created_at AT TIME ZONE 'UTC' AT TIME ZONE #{zone})")
      scope = FlashcardRun.where(user: actor)
      days = scope.group(date).order(date.desc).limit(7).pluck(date)
      days.map do |day|
        daily = scope.where(created_at: day.in_time_zone.all_day)
        cards = FlashcardCard.where(flashcard_run_id: daily.select(:id)).where.not(answered_at: nil)
        attempted = cards.count
        {day: day, runs: daily.count, attempted: attempted,
         completion: (100.0 * attempted / daily.sum(:planned_count)).round,
         accuracy: attempted.zero? ? 0 : (100.0 * cards.where(correct: true).count / attempted).round}
      end
    end

    private

    def distractors(people, person)
      candidates = people.where.not(display_name: person.display_name)
      # Gender is used only if this custom attribute is explicitly allowlisted.
      gender = person.custom_attributes["Gender"] if policy.attribute_keys.include?("Gender")
      order = if gender.present?
        quoted = PersonProfile.connection.quote(gender.to_s)
        "CASE WHEN custom_attributes->>'Gender' = #{quoted} THEN 0 ELSE 1 END, RANDOM()"
      else
        "RANDOM()"
      end
      # Deduplicate in SQL so large pools don't load thousands of profiles per card.
      distinct = candidates.select("DISTINCT ON (display_name) person_profiles.*")
        .reorder(Arel.sql("display_name, #{order}"))
      PersonProfile.from("(#{distinct.to_sql}) person_profiles")
        .order(Arel.sql(order)).limit(3).pluck(:id)
    end

    def pool(campuses, statuses)
      ids = statuses.map { |id| (id == "unknown") ? nil : id.to_i }
      available.where(campus_id: campuses, connection_status_id: ids)
    end

    def select_people(people, count)
      connection = PersonProfile.connection
      user_id = connection.quote(actor.id)
      now = connection.quote(Time.current)
      people.joins("LEFT JOIN flashcard_reviews ON " \
        "flashcard_reviews.person_profile_id = person_profiles.id " \
        "AND flashcard_reviews.user_id = #{user_id}")
        .order(Arel.sql("CASE WHEN flashcard_reviews.due_at <= #{now} THEN 0 " \
          "WHEN flashcard_reviews.id IS NULL THEN 1 ELSE 2 END, " \
          "flashcard_reviews.due_at ASC NULLS LAST, RANDOM()"))
        .limit(count).to_a
    end
  end
end
