require "fileutils"
require "minitest/autorun"
require "open3"
require "shellwords"
require "tmpdir"

class DevcontainerSetupTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("prosecho-setup-")
    FileUtils.mkdir_p(File.join(@dir, "bin"))
    File.write(File.join(@dir, "Gemfile.lock"), "fixture lock\n")
    @env = {"PATH" => "#{@dir}/bin:#{ENV.fetch("PATH")}",
            "DATABASE_URL" => nil, "RACK_ENV" => nil, "RAILS_ENV" => nil}
    @logs_mount = File.join(@dir, "logs mount")
    @logs_link = File.join(@dir, "work logs")
    FileUtils.mkdir_p(File.join(@dir, ".devcontainer"))
    FileUtils.cp(File.join(__dir__, "post-attach.sh"), File.join(@dir, ".devcontainer"))
    # Redirect only the optional mount to a fixture; never inspect the live /work-logs.
    File.write(File.join(@dir, ".devcontainer/link-work-logs.sh"), <<~SH)
      exec sh #{File.join(__dir__, "link-work-logs.sh").shellescape} \
        #{@logs_mount.shellescape} #{@dir.shellescape}
    SH
    stub("bundle", <<~SH)
      printf 'bundle %s frozen=%s\n' "$*" "$BUNDLE_FROZEN" >> calls
      if [ "$1" = check ]; then
        printf 'expected cache miss\n' >&2
        exit "${CHECK_STATUS:-0}"
      fi
      printf 'install diagnostic\n' >&2
      exit "${INSTALL_STATUS:-0}"
    SH
    stub("pg_isready", <<~SH)
      printf 'probe %s\n' "$*" >> calls
      exit "${PROBE_STATUS:-0}"
    SH
    stub("psql", <<~SH)
      printf 'authenticate timeout=%s %s\n' "$PGCONNECT_TIMEOUT" "$*" >> calls
      printf 'authentication diagnostic\n' >&2
      exit "${AUTH_STATUS:-0}"
    SH
    stub("rails", <<~SH)
      printf 'rails %s env=%s timeout=%s\n' "$1" "$RAILS_ENV" "$PGCONNECT_TIMEOUT" >> calls
      printf 'rails diagnostic\n' >&2
      if [ "$1" = runner ] && [ "${RAILS_STATUS:-0}" = 0 ]; then
        exec ruby -r ./readiness.rb -e "$2"
      fi
      exit "${RAILS_STATUS:-0}"
    SH
    File.write(File.join(@dir, "readiness.rb"), <<~RUBY)
      class FixturePool
        def migration_context
          self
        end

        def needs_migration?
          ENV["PENDING_MIGRATIONS"] == "true"
        end

        def with_connection
          connection = Object.new
          def connection.select_value(sql)
            raise "Unexpected SQL" unless sql == "SELECT 1"
            1
          end
          yield connection
        end
      end

      module ActiveRecord
        class Base
          def self.connection_pool
            FixturePool.new
          end
        end
      end
    RUBY
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_authentication_and_migration_errors_are_not_optional
    [{"AUTH_STATUS" => "2"}, {"RAILS_STATUS" => "1"}].each do |env|
      output, status = run_script("setup.sh", "--automatic", env: env)
      refute status.success?, output
      refute_includes output, "PostgreSQL unavailable"
      assert_includes output, "failed"
      refute File.exist?(File.join(@dir, "tmp/devcontainer-setup.lock"))
    end
  end

  def test_available_setup_installs_locked_dependencies_in_both_modes
    [[], ["--automatic"]].each do |args|
      output, status = run_script("setup.sh", *args, env: {"CHECK_STATUS" => "1"})
      assert status.success?, output
      assert_includes output, "Ready:"
      refute_includes output, "expected cache miss"
      assert_includes calls, "bundle install frozen=true"
      assert_includes calls, "authenticate timeout=3"
      assert_includes calls, "rails db:prepare env=development"
      refute File.exist?(File.join(@dir, "tmp/devcontainer-setup.lock"))
    end
  end

  def test_existing_bundle_does_not_install
    output, status = run_script("setup.sh", "--automatic")
    assert status.success?, output
    refute_includes calls, "bundle install"
    assert_includes calls, "rails db:prepare"
  end

  def test_install_failure_is_visible_and_nonzero_in_both_modes
    [[], ["--automatic"]].each do |args|
      output, status = run_script("setup.sh", *args,
        env: {"CHECK_STATUS" => "1", "INSTALL_STATUS" => "1"})
      refute status.success?
      assert_includes output, "install diagnostic"
      assert_includes output, "Dependency installation failed"
      refute_includes calls, "probe"
    end
  end

  def test_lock_is_preserved_and_prevents_work
    FileUtils.mkdir_p(File.join(@dir, "tmp/devcontainer-setup.lock"))
    output, status = run_script("setup.sh", "--automatic")
    refute status.success?
    assert_includes output, "Setup already running or stale lock"
    assert File.directory?(File.join(@dir, "tmp/devcontainer-setup.lock"))
    assert_empty calls
  end

  def test_logs_absent_or_non_directory_creates_no_placeholder
    2.times do |attempt|
      File.write(@logs_mount, "not a directory") if attempt == 1
      output, status = run_script("link-work-logs.sh", @logs_mount, @dir)
      assert status.success?, output
      refute File.exist?(@logs_link)
      refute File.symlink?(@logs_link)
    end
  end

  def test_logs_conflicts_are_preserved_with_or_without_mount
    [false, true].each do |mounted|
      FileUtils.mkdir_p(@logs_mount) if mounted
      [:file, :directory, :symlink, :dangling_symlink].each do |kind|
        case kind
        when :file then File.write(@logs_link, "keep file")
        when :directory
          Dir.mkdir(@logs_link)
          File.write(File.join(@logs_link, "keep"), "keep directory")
        when :symlink then File.symlink(@dir, @logs_link)
        when :dangling_symlink then File.symlink("/work-logs/", @logs_link)
        end
        before = File.lstat(@logs_link)
        output, status = run_script("link-work-logs.sh", @logs_mount, @dir)
        assert status.success?, output
        assert_includes output, "Warning:"
        assert_includes output, "preserving existing"
        assert_equal before.ino, File.lstat(@logs_link).ino
        case kind
        when :file then assert_equal "keep file", File.read(@logs_link)
        when :directory then assert_equal "keep directory", File.read(File.join(@logs_link, "keep"))
        when :symlink then assert_equal @dir, File.readlink(@logs_link)
        when :dangling_symlink then assert_equal "/work-logs/", File.readlink(@logs_link)
        end
        FileUtils.remove_entry(@logs_link)
      end
    end
  end

  def test_logs_link_is_idempotent_and_removed_when_mount_disappears
    Dir.mkdir(@logs_mount)
    File.write(File.join(@logs_mount, "keep"), "keep logs")
    output, status = run_script("link-work-logs.sh", @logs_mount, @dir)
    assert status.success?, output
    assert_equal @logs_mount, File.readlink(@logs_link)
    before = File.lstat(@logs_link)
    output, status = run_script("link-work-logs.sh", @logs_mount, @dir)
    assert status.success?, output
    assert_equal before.ino, File.lstat(@logs_link).ino
    assert_equal "keep logs", File.read(File.join(@logs_mount, "keep"))
    File.rename(@logs_mount, "#{@logs_mount} removed")
    2.times do
      output, status = run_script("link-work-logs.sh", @logs_mount, @dir)
      assert status.success?, output
      refute File.symlink?(@logs_link)
      refute File.exist?(@logs_link)
    end
    assert_equal "keep logs", File.read(File.join("#{@logs_mount} removed", "keep"))
  end

  def test_logs_workspace_defaults_to_script_parent_not_current_directory
    Dir.mkdir(@logs_mount)
    script = File.join(@dir, ".devcontainer/link-work-logs.sh")
    FileUtils.cp(File.join(__dir__, "link-work-logs.sh"), script)
    output, status = Open3.capture2e("sh", script, @logs_mount, chdir: File.join(@dir, "bin"))
    assert status.success?, output
    assert_equal @logs_mount, File.readlink(@logs_link)
    refute File.symlink?(File.join(@dir, "bin/work logs"))
  end

  def test_missing_lockfile_fails_in_both_modes
    File.unlink(File.join(@dir, "Gemfile.lock"))
    [[], ["--automatic"]].each do |args|
      output, status = run_script("setup.sh", *args)
      refute status.success?
      assert_includes output, "Gemfile.lock is missing"
      assert_empty calls
    end
  end

  def test_post_attach_probe_errors_are_visible_without_blocking_attachment
    %w[3 127].each do |probe_status|
      output, status = run_script("post-attach.sh", env: {"PROBE_STATUS" => probe_status})
      assert status.success?, output
      assert_includes output, "probe failed (status #{probe_status})"
      assert_includes output, "check pg_isready and its configuration"
      refute_includes output, "PostgreSQL unavailable"
      refute_includes output, "database setup pending"
      refute_includes output, "Ready:"
      refute_includes calls, "rails runner"
    end
  end

  def test_post_attach_link_failure_does_not_block_readiness
    File.write(File.join(@dir, ".devcontainer/link-work-logs.sh"), "exit 1\n")
    output, status = run_script("post-attach.sh")
    assert status.success?, output
    assert_includes output, "optional work logs link could not be updated"
    assert_includes output, "Ready:"
    refute_includes calls, "db:prepare"
  end

  def test_post_attach_links_logs_before_readiness_guards
    Dir.mkdir(@logs_mount)
    File.unlink(File.join(@dir, "Gemfile.lock"))
    output, status = run_script("post-attach.sh")
    assert status.success?, output
    assert_includes output, "dependencies NOT ready"
    assert_equal @logs_mount, File.readlink(@logs_link)
    assert_empty calls
    File.unlink(@logs_link)
    File.write(@logs_link, "keep conflict")
    output, status = run_script("post-attach.sh")
    assert status.success?, output
    assert_includes output, "Warning:"
    assert_includes output, "dependencies NOT ready"
    assert_equal "keep conflict", File.read(@logs_link)
  end

  def test_post_attach_reports_current_readiness_without_mutation
    output, status = run_script("post-attach.sh")
    assert status.success?, output
    assert_includes output, "Ready:"
    refute_includes output, "resume"
    [{"CHECK_STATUS" => "1"}, {"RAILS_STATUS" => "1"},
      {"PENDING_MIGRATIONS" => "true"}].each do |env|
      output, status = run_script("post-attach.sh", env: env)
      assert status.success?, output
      assert_includes output, "NOT ready"
      assert_includes output, "sh .devcontainer/setup.sh"
      refute_includes output, "Ready:"
      assert_includes output, "rails diagnostic" if env["RAILS_STATUS"]
      assert_includes output, "Pending migrations" if env["PENDING_MIGRATIONS"]
    end
    output, status = run_script("post-attach.sh")
    assert status.success?, output
    assert_includes output, "Ready:"
    refute_includes calls, "install"
    refute_includes calls, "db:prepare"
  end

  def test_post_attach_unavailable_database_skips_rails_and_reports_resumption
    %w[1 2].each do |probe_status|
      output, status = run_script("post-attach.sh", env: {"PROBE_STATUS" => probe_status})
      assert status.success?, output
      assert_includes output, "Shell ready; dependencies ready"
      assert_includes output, "PostgreSQL unavailable (database setup pending)"
      assert_includes output, "On the host"
      assert_includes output, "podman-compose -p prosecho -f .devcontainer/compose.yaml " \
        "-f .devcontainer/compose.runtime.yaml up -d postgres"
      refute_includes output, "--profile"
      assert_includes output, "docker compose"
      assert_includes output, "Then in the container resume: sh .devcontainer/setup.sh"
      refute_includes output, "rails diagnostic"
      refute_includes output, "Ready:"
      assert_includes calls, "probe -q -t 3 -d postgres"
      refute_includes calls, "rails runner"
      refute_includes calls, "authenticate"
    end
  end

  def test_probe_implementation_errors_are_not_optional
    output, status = run_script("setup.sh", "--automatic", env: {"PROBE_STATUS" => "3"})
    refute status.success?
    assert_includes output, "probe failed"
    refute_includes output, "PostgreSQL unavailable"
    stub("pg_isready", "exit 127")
    output, status = run_script("setup.sh", "--automatic")
    refute status.success?
    assert_includes output, "probe failed"
  end

  def test_production_overrides_are_rejected_before_database_work
    [{"RAILS_ENV" => "production"}, {"RACK_ENV" => "production"},
      {"DATABASE_URL" => "postgres://fixture/production"}].each do |env|
      output, status = run_script("setup.sh", "--automatic", env: env)
      refute status.success?
      assert_includes output, "development"
      assert_empty calls
    end
  end

  def test_unavailable_database_is_pending_only_in_automatic_mode
    %w[1 2].each do |probe_status|
      [[], ["--automatic"]].each do |args|
        output, status = run_script("setup.sh", *args,
          env: {"CHECK_STATUS" => "1", "PROBE_STATUS" => probe_status})
        assert_equal !args.empty?, status.success?, output
        assert_includes output, "PostgreSQL unavailable"
        assert_includes output, "-f .devcontainer/compose.runtime.yaml up -d postgres"
        refute_includes output, "--profile"
        assert_includes output, "sh .devcontainer/setup.sh"
        assert_includes calls, "bundle install frozen=true"
        refute_includes calls, "rails db:prepare"
        refute_includes calls, "authenticate"
      end
    end
  end

  private

  def calls
    path = File.join(@dir, "calls")
    File.exist?(path) ? File.read(path) : ""
  end

  def run_script(name, *args, env: {})
    path = (name == "post-attach.sh") ? File.join(@dir, ".devcontainer", name) :
      File.expand_path(name, __dir__)
    output, status = Open3.capture2e(@env.merge(env), "sh",
      path, *args, chdir: @dir)
    [output, status]
  end

  def stub(name, body)
    path = File.join(@dir, "bin", name)
    File.write(path, "#!/bin/sh\n#{body}\n")
    File.chmod(0o700, path)
  end
end
