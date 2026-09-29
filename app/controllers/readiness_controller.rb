class ReadinessController < ActionController::API
  def show
    pool = ActiveRecord::Base.connection_pool
    pool.with_connection do |connection|
      raise ActiveRecord::ConnectionNotEstablished unless connection.select_value("SELECT 1").to_i == 1
      if pool.migration_context.needs_migration?
        return render plain: "not ready\n", status: :service_unavailable
      end
    end
    render plain: "ready\n"
  rescue ActiveRecord::ActiveRecordError, PG::Error
    render plain: "not ready\n", status: :service_unavailable
  end
end
