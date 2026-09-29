require "test_helper"
require "pg"
load File.expand_path("../../bin/prod/deploy", __dir__) unless defined?(ProsechoDeploy)

class DatabaseBootstrapTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "real local PostgreSQL app role can migrate its own database but cannot administer the cluster" do
    role = "prosecho_bootstrap_test_#{Process.pid}_#{SecureRandom.hex(4)}"
    database = role
    password = "a" * 64
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    admin = PG.connect(host: config[:host], port: config[:port], user: config[:username], password: config[:password], dbname: config[:database])
    app = nil
    begin
      runner = ProsechoDeploy::Runner.new
      command = ["psql", "-X", "-q", "-w", "-v", "ON_ERROR_STOP=1", "-h", config[:host], "-p", config[:port].to_s, "-U", config[:username], "-d", config[:database]]
      runner.run(*command, input: ProsechoDeploy.bootstrap_sql(password, role: role, database: database), capture: true)
      # A retry must preserve the database and the same bounded role privileges.
      runner.run(*command, input: ProsechoDeploy.bootstrap_sql(password, role: role, database: database), capture: true)
      flags = admin.exec_params("SELECT rolsuper, rolcreatedb, rolcreaterole, rolreplication, rolbypassrls FROM pg_roles WHERE rolname = $1", [role]).first
      assert_equal ["f"] * 5, flags.values
      app = PG.connect(host: config[:host], port: config[:port], user: role, password: password, dbname: database)
      assert_equal "1", app.exec("SELECT 1").getvalue(0, 0)
      app.exec("CREATE TABLE migration_probe (id bigint PRIMARY KEY)")
      app.exec("ALTER TABLE migration_probe ADD COLUMN body text")
      app.exec("DROP TABLE migration_probe")
      assert_raises(PG::InsufficientPrivilege) { app.exec("CREATE ROLE forbidden_probe") }
      assert_raises(PG::InsufficientPrivilege) { app.exec("CREATE DATABASE forbidden_probe") }
      assert_raises(PG::InsufficientPrivilege) { app.exec("SELECT * FROM pg_authid") }
    ensure
      app&.close
      admin.exec("DROP DATABASE IF EXISTS #{database}")
      admin.exec("DROP ROLE IF EXISTS #{role}")
      admin.close
    end
  end
end
