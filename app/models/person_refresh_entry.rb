class PersonRefreshEntry < ApplicationRecord
  belongs_to :run, class_name: "PersonRefreshRun"

  def self.checkpoint!(run:, people:, observed_at:)
    columns = %w[run_id rock_guid payload observed_at]
    binds = []
    values = people.map do |person|
      attributes = {"run_id" => run.id, "rock_guid" => person.rock_guid,
                    "payload" => person.to_h.as_json, "observed_at" => observed_at}
      placeholders = columns.map do |column|
        binds << ActiveRecord::Relation::QueryAttribute.new(column, attributes.fetch(column),
          type_for_attribute(column))
        "$#{binds.size}"
      end
      "(#{placeholders.join(", ")}, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)"
    end
    return if values.empty?

    # Rails upsert_all embeds JSON literals in its SQL, bypassing bind filtering.
    # Keep the batch upsert, but bind private payloads so SQL logs can redact them.
    sql = "INSERT INTO person_refresh_entries " \
      "(run_id, rock_guid, payload, observed_at, created_at, updated_at) " \
      "VALUES #{values.join(", ")} ON CONFLICT (run_id, rock_guid) DO UPDATE SET " \
      "payload = EXCLUDED.payload, observed_at = EXCLUDED.observed_at, updated_at = CURRENT_TIMESTAMP"
    connection.exec_query(sql, "Person staging checkpoint", binds)
  end
end
