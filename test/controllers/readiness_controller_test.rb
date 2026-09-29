require "test_helper"
require "tmpdir"

class ReadinessControllerTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  test "real PostgreSQL connection and migration context are ready" do
    ActiveRecord::Base.connection_pool.with_connection { |connection| assert_equal "PostgreSQL", connection.adapter_name }
    get "/ready"
    assert_response :success
    assert_equal "ready\n", response.body
  end

  test "a real failed database connection returns generic 503" do
    original = ActiveRecord::Base.connection_db_config
    begin
      ActiveRecord::Base.establish_connection(original.configuration_hash.merge(host: "127.0.0.1", port: 1, connect_timeout: 1))
      get "/ready"
      assert_response :service_unavailable
      assert_equal "not ready\n", response.body
    ensure
      ActiveRecord::Base.establish_connection(original)
    end
  end

  test "real migration context detects an unapplied migration" do
    original = ActiveRecord::Migrator.migrations_paths
    Dir.mktmpdir do |directory|
      File.write(File.join(directory, "20200101000000_readiness_probe.rb"), "class ReadinessProbe < ActiveRecord::Migration[8.1]; def change; end; end\n")
      begin
        ActiveRecord::Migrator.migrations_paths = [directory]
        assert ActiveRecord::Base.connection_pool.migration_context.needs_migration?
        get "/ready"
        assert_response :service_unavailable
        assert_equal "not ready\n", response.body
      ensure
        ActiveRecord::Migrator.migrations_paths = original
      end
    end
  end
end
