module Access
  class Provisioner
    ACCOUNT_LOCK = 73003000
    ACCOUNT_SETTINGS = %i[active email password password_confirmation role
      view_history view_locations view_photos].freeze
    CampusImportResult = Data.define(:created, :updated, :unchanged)
    class NotAuthorized < StandardError; end

    def self.bootstrap(email:, password:, password_confirmation: nil)
      User.transaction do
        # Serialize the one-time bootstrap; two operators cannot both become the first admin.
        User.connection.execute("SELECT pg_advisory_xact_lock(#{ACCOUNT_LOCK})")
        raise NotAuthorized, "Bootstrap is only available before the first account" if User.exists?

        user = User.create!(email: email, password: password,
          password_confirmation: password_confirmation, role: "administrator")
        AccessEvent.create!(actor: user, resource: "account", resource_id: user.id,
          outcome: "provisioned")
        user
      end
    end

    def initialize(actor:)
      @actor = actor
    end

    def grant(user:, campus:)
      with_administrator do
        grant = CampusAccess.find_or_create_by!(campus: campus, user: user)
        AccessEvent.create!(actor: @actor, resource: "campus_access", resource_id: grant.id,
          outcome: "updated")
      end
    end

    def import_campuses(records)
      with_administrator do
        counts = {created: 0, updated: 0, unchanged: 0}
        records.each do |record|
          campus = Campus.find_or_initialize_by(rock_id: record.fetch(:rock_id))
          outcome = campus.new_record? ? :created : :updated
          # Rock has no parent-campus field. Preserve local parents and UUIDs so
          # refreshes cannot duplicate campuses or erase existing staff grants.
          campus.assign_attributes(record.slice(:active, :name))
          unless campus.changed?
            counts[:unchanged] += 1
            next
          end
          campus.save!
          counts[outcome] += 1
          AccessEvent.create!(actor: @actor, resource: "campus", resource_id: campus.id,
            outcome: (outcome == :created) ? "provisioned" : "updated")
        end
        CampusImportResult.new(**counts)
      end
    end

    def provision(email:, password:, password_confirmation: nil, attributes: {}, campus_ids: [])
      validate_settings!(attributes)
      with_administrator do
        user = User.create!(attributes.merge(email: email, password: password,
          password_confirmation: password_confirmation))
        assign_campuses!(user, campus_ids)
        AccessEvent.create!(actor: @actor, resource: "account", resource_id: user.id,
          outcome: "provisioned")
        user
      end
    end

    def revoke(user:, campus:)
      with_administrator do
        grant = CampusAccess.find_by!(campus: campus, user: user)
        AccessEvent.create!(actor: @actor, resource: "campus_access", resource_id: grant.id,
          outcome: "revoked")
        grant.destroy!
      end
    end

    def save_campus(campus:, attributes:)
      allowed = %i[active name parent_id rock_id]
      raise ArgumentError, "Unsupported campus setting" unless (attributes.keys - allowed).empty?

      with_administrator do
        campus.update!(attributes)
        AccessEvent.create!(actor: @actor, resource: "campus", resource_id: campus.id,
          outcome: "updated")
        campus
      end
    end

    def save_data_policy(attributes:, revision:)
      allowed = DataPolicy::RETENTION_FIELDS + DataPolicy::TEXT_FIELDS +
        %i[attribute_keys_text retention_notes selected_fields status]
      raise ArgumentError, "Unsupported policy setting" unless (attributes.keys - allowed).empty?

      with_administrator do
        policy = DataPolicy.current
        raise DataPolicy::Conflict unless policy.revision == revision

        policy.assign_attributes(attributes)
        policy.recorded_by = @actor
        policy.confirmed_at = policy.confirmed? ? Time.current : nil
        policy.confirmed_by = policy.confirmed? ? @actor : nil
        policy.save!
        AccessEvent.create!(actor: @actor, resource: "data_policy", resource_id: policy.id,
          outcome: "updated")
        policy
      end
    end

    def update(user:, attributes:, campus_ids: nil)
      validate_settings!(attributes)
      with_administrator do
        user.assign_attributes(attributes)
        protect_last_administrator!(user)
        user.save!
        assign_campuses!(user, campus_ids) unless campus_ids.nil?
        AccessEvent.create!(actor: @actor, resource: "account", resource_id: user.id,
          outcome: "updated")
      end
    end

    private

    def assign_campuses!(user, campus_ids)
      ids = Array(campus_ids).reject(&:blank?).map(&:to_s).uniq
      valid = ids.all? { |id| id.match?(/\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/i) }
      campuses = valid ? Campus.where(id: ids).to_a : []
      if !valid || campuses.size != ids.size
        user.errors.add(:base, "Choose existing campuses")
        raise ActiveRecord::RecordInvalid, user
      end
      user.campuses = campuses
    end

    def authorize!
      unless @actor&.reload&.administrator? && !@actor.access_locked?
        raise NotAuthorized, "An active administrator is required"
      end
    end

    def protect_last_administrator!(user)
      removing_admin = user.role_in_database == "administrator" && user.active_in_database &&
        !(user.active? && user.role == "administrator")
      others = User.where(role: "administrator", active: true).where.not(id: user.id)
      if removing_admin && !others.exists?
        user.errors.add(:base, "Cannot remove the last active administrator")
        raise ActiveRecord::RecordInvalid, user
      end
    end

    def validate_settings!(attributes)
      unless (attributes.keys - ACCOUNT_SETTINGS).empty?
        raise ArgumentError, "Unsupported account setting"
      end
    end

    def with_administrator
      User.transaction do
        User.connection.execute("SELECT pg_advisory_xact_lock(#{ACCOUNT_LOCK})")
        authorize!
        yield
      end
    end
  end
end
