module ChurchNext
  class NameMatcher
    MAX_CANDIDATES = 8

    def suggestions(account:, scope:)
      # Bound fuzzy comparisons using PostgreSQL's indexed trigram shortlist.
      # Bind names rather than interpolate them: query logs must not retain PII.
      type = PersonProfile.type_for_attribute("last_name")
      binds = [ActiveRecord::Relation::QueryAttribute.new("last_name", account.last_name, type),
        ActiveRecord::Relation::QueryAttribute.new("first_name", account.first_name, type)]
      sql = "SELECT id FROM person_profiles WHERE id IN (#{scope.select(:id).to_sql}) " \
        "AND last_name % $1 ORDER BY " \
        "similarity(last_name, $1) + GREATEST(similarity(first_name, $2), " \
        "COALESCE(similarity(nick_name, $2), 0)) DESC, id LIMIT 200"
      ids = PersonProfile.connection.exec_query(sql, "ChurchNext name shortlist", binds).rows.flatten
      scope.where(id: ids).filter_map do |person|
        last = similarity(account.last_name, person.last_name)
        first = [person.first_name, person.nick_name].compact.map do |name|
          similarity(account.first_name, name)
        end.max || 0
        next unless last >= 0.88 && first >= 0.80

        score = (100 * (0.55 * last + 0.45 * first)).round
        {person: person, score: score, reason: "name"} if score >= 86
      end.sort_by { |entry| [-entry[:score], entry[:person].id] }.first(MAX_CANDIDATES)
    end

    private

    def normalize(value)
      value.to_s.unicode_normalize(:nfkd).downcase(:fold)
        .gsub(/\p{Mn}/, "").gsub(/[^\p{L}\p{N}]/, "")
    end

    def similarity(left, right)
      left, right = normalize(left), normalize(right)
      return 0.0 if left.empty? || right.empty?
      return 1.0 if left == right

      # Jaro-Winkler tolerates transpositions/typos and rewards shared name prefixes.
      distance = [([left.length, right.length].max / 2) - 1, 0].max
      left_matches, right_matches = Array.new(left.length, false), Array.new(right.length, false)
      matches = 0
      left.chars.each_with_index do |character, index|
        ([index - distance, 0].max..[index + distance, right.length - 1].min).each do |other|
          next if right_matches[other] || character != right[other]
          left_matches[index] = right_matches[other] = true
          matches += 1
          break
        end
      end
      return 0.0 if matches.zero?

      lhs = left.chars.each_with_index.filter_map { |char, index| char if left_matches[index] }
      rhs = right.chars.each_with_index.filter_map { |char, index| char if right_matches[index] }
      transpositions = lhs.zip(rhs).count { |a, b| a != b } / 2.0
      jaro = (matches.to_f / left.length + matches.to_f / right.length +
        (matches - transpositions) / matches) / 3
      prefix = (0...[left.length, right.length, 4].min).take_while { |i| left[i] == right[i] }.length
      (jaro > 0.7) ? jaro + prefix * 0.1 * (1 - jaro) : jaro
    end
  end
end
