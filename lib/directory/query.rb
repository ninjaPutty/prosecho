module Directory
  class Query
    PAGE_SIZE = 24
    attr_reader :errors, :filters, :options, :page, :people, :policy, :total

    def initialize(actor:, filters: {}, page: 1)
      @policy = DataPolicy.current
      @scope = PersonProfile.visible_to(actor, policy: @policy)
      @filters = filters.to_h.stringify_keys.slice("campus_id", "connection_status",
        "min_age", "max_age", "town", "search").transform_values(&:to_s)
      @errors = []
      @page = page.to_i.clamp(1, 10000)
      @options = {
        campuses: actor.campuses.active.order(:name).to_a,
        statuses: @scope.distinct.pluck(:connection_status_id, :connection_status_label),
        towns: @scope.where.not(city: [nil, ""]).distinct.order(:city).pluck(:city)
      }
      validate_filters
      results = apply_filters
      @total = results.count
      @people = results.includes(:campus).order(:display_name, :id)
        .limit(PAGE_SIZE).offset((@page - 1) * PAGE_SIZE).to_a
    end

    def confirmed?
      policy.persisted? && policy.confirmed? && policy.valid?
    end

    def last_observed_at
      @scope.maximum(:observed_at)
    end

    private

    def apply_filters
      return @scope.none if errors.any?
      result = @scope
      result = result.where(campus_id: filters["campus_id"]) if filters["campus_id"].present?
      if filters["connection_status"].present?
        id = (filters["connection_status"] == "unknown") ? nil : filters["connection_status"].to_i
        result = result.where(connection_status_id: id)
      end
      result = result.where(city: filters["town"]) if filters["town"].present?
      if filters["search"].present?
        term = "%#{PersonProfile.sanitize_sql_like(filters["search"])}%"
        result = result.where("display_name ILIKE ?", term)
      end
      %w[min_age max_age].each do |key|
        next if filters[key].blank?
        comparison = (key == "min_age") ? ">=" : "<="
        result = result.where("DATE_PART('year', AGE(?::date, birth_date)) #{comparison} ?",
          Date.current, filters[key].to_i)
      end
      result
    end

    def validate_filters
      campus = filters["campus_id"]
      if campus.present? && !options[:campuses].any? { |value| value.id == campus }
        errors << "Choose one of your assigned campuses."
      end
      status = filters["connection_status"]
      if status.present? && status != "unknown" &&
          !options[:statuses].any? { |id, _| id.to_s == status }
        errors << "Choose an available connection status."
      end
      if filters["town"].present? && !options[:towns].include?(filters["town"])
        errors << "Choose an available home town."
      end
      %w[min_age max_age].each do |key|
        value = filters[key]
        if value.present? && !(value.match?(/\A\d{1,3}\z/) && value.to_i.between?(0, 130))
          errors << "Ages must be whole numbers from 0 to 130."
        end
      end
      if filters["min_age"].present? && filters["max_age"].present? &&
          filters["min_age"].to_i > filters["max_age"].to_i
        errors << "Minimum age must not exceed maximum age."
      end
      errors << "Keep the name search to 100 characters." if filters["search"].to_s.length > 100
    end
  end
end
