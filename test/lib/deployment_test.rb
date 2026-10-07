require "test_helper"
require "minitest/mock"
require "open3"
require "tmpdir"
load File.expand_path("../../bin/prod/deploy", __dir__) unless defined?(ProsechoDeploy)

class DeploymentTest < ActiveSupport::TestCase
  SHA = "a" * 40

  test "first install waits and prepares once before starting proxy and switching" do
    commands = ProsechoDeploy.phases("first", SHA)
    text = commands.map { |command| command.join(" ") }
    wait = text.index { |command| command.include?("SELECT 1") }
    prepare = text.index { |command| command.include?("db:prepare") }
    proxy = text.index { |command| command.include?("proxy boot") }
    switch = text.index { |command| command.include?("redeploy --skip-push") }
    assert_operator wait, :<, prepare
    assert_operator prepare, :<, proxy
    assert_operator proxy, :<, switch
    assert_includes text[prepare], "test -f ~/.local/share/prosecho/db-prepared"
    assert_includes text[prepare], "--env-file /dev/stdin"
    assert text.none? { |command| command.match?(/prune|kamal setup|context/) }
    assert_includes text.first, "build push --version #{SHA}"
  end

  test "later deploy requires explicit migration without reinitializing accessories" do
    text = ProsechoDeploy.phases("migrate", SHA).map { |command| command.join(" ") }
    assert text.any? { |command| command.include?("db:migrate") }
    assert text.none? { |command| command.match?(/db:prepare|proxy boot|accessory boot|prune/) }
  end

  test "rollback verifies a retained container and never builds or migrates" do
    text = ProsechoDeploy.phases("rollback", SHA).map { |command| command.join(" ") }
    assert_includes text.first, "docker inspect prosecho-web-#{SHA}"
    assert_includes text[1], "kamal rollback #{SHA}"
    assert text.none? { |command| command.match?(/build|db:|prune/) }
    assert_includes text.last, "/ready"
  end

  test "invalid dirty or mismatched revisions cannot pass the SHA gate" do
    assert_raises(ProsechoDeploy::Failure) { ProsechoDeploy.clean_sha!("latest") }
    ["mismatch", "dirty", "clean"].each do |state|
      runner = Object.new
      runner.define_singleton_method(:run) do |*command, **_options|
        if command.include?("HEAD")
          (state == "mismatch") ? "b" * 40 : SHA
        else
          ((state == "dirty") ? " M Gemfile" : "")
        end
      end
      if state == "clean"
        ProsechoDeploy.clean_sha!(SHA, runner)
      else
        assert_raises(ProsechoDeploy::Failure) { ProsechoDeploy.clean_sha!(SHA, runner) }
      end
    end
  end

  test "remote shell programs have valid syntax" do
    [ProsechoDeploy::LOCK, ProsechoDeploy::DATABASE_WAIT, ProsechoDeploy.artifact_script(SHA), ProsechoDeploy.artifact_script(SHA, record: true), *ProsechoDeploy.phases("first", SHA).select { |command| command.include?("ssh") }.map(&:last)].each do |script|
      _output, status = Open3.capture2("sh", "-n", stdin_data: script)
      assert status.success?, script
    end
    assert system("sh", "-n", "bin/prod/cloudflare-ssh")
    assert system("sh", "-n", "bin/prod/docker")
    assert system("sh", "-n", ".kamal/secrets")
  end

  test "Cloudflare helper clears Access credentials without reading token files" do
    Dir.mktmpdir do |directory|
      scripts = {
        "stat" => "exit 99",
        "jq" => "exit 99",
        "cloudflared" => 'test -z "${TUNNEL_SERVICE_TOKEN_ID+set}" && test -z "${TUNNEL_SERVICE_TOKEN_SECRET+set}" && printf "%s\\n" "$*"'
      }
      scripts.each do |name, script|
        path = File.join(directory, name)
        File.write(path, "#!/bin/sh\n#{script}\n")
        File.chmod(0o700, path)
      end
      env = {"PATH" => "#{directory}:/usr/bin:/bin", "CF_SSH_HOST" => "fake.example",
             "PROSECHO_CF_AUTH" => nil, "TUNNEL_SERVICE_TOKEN_ID" => "fake-id",
             "TUNNEL_SERVICE_TOKEN_SECRET" => "fake-secret"}
      output, error, status = Open3.capture3(env, "sh", "bin/prod/cloudflare-ssh")
      assert status.success?
      assert_empty error
      assert_equal "access ssh --hostname fake.example\n", output
      assert_not_includes output, "fake-secret"
    end
  end

  test "immutable registry gate rejects unknown tags and changed digests" do
    Dir.mktmpdir do |directory|
      curl = File.join(directory, "curl")
      digest = "sha256:" + "b" * 64
      File.write(curl, "#!/bin/sh\ncase \"$*\" in *http_code*) printf 200;; *) printf 'Docker-Content-Digest: #{digest}\\r\\n';; esac\n")
      File.chmod(0o700, curl)
      env = {"HOME" => directory, "PATH" => "#{directory}:/usr/bin:/bin"}
      _output, status = Open3.capture2(env, "sh", "-c", ProsechoDeploy.artifact_script(SHA))
      assert_not status.success?, "unrecorded existing tag must not be adopted"
      output, status = Open3.capture2(env, "sh", "-c", ProsechoDeploy.artifact_script(SHA, record: true))
      assert status.success?
      assert_equal digest, output
      output, status = Open3.capture2(env, "sh", "-c", ProsechoDeploy.artifact_script(SHA))
      assert status.success?
      assert_equal digest, output
      File.write(File.join(directory, ".local/share/prosecho/images", SHA), "sha256:" + "c" * 64)
      _output, status = Open3.capture2(env, "sh", "-c", ProsechoDeploy.artifact_script(SHA))
      assert_not status.success?, "changing a tag must block deployment"
    end
  end

  test "loopback registry login uses SSH and sends password only on stdin" do
    Dir.mktmpdir do |directory|
      ssh = File.join(directory, "ssh")
      File.write(ssh, "#!/bin/sh\n" + 'read -r password; test "$password" = fake-placeholder && printf "%s\n" "$*"' + "\n")
      File.chmod(0o700, ssh)
      env = {"PATH" => "#{directory}:/usr/bin:/bin", "DOCKER_HOST" => ProsechoDeploy::DOCKER_HOST}
      output, status = Open3.capture2(env, "sh", "bin/prod/docker", "login", "127.0.0.1:5555", "-u", "prosecho", "-p", "fake-placeholder")
      assert status.success?
      assert_includes output, "prosecho-deploy-cloudflare docker login 127.0.0.1:5555 -u prosecho --password-stdin"
      assert_not_includes output, "fake-placeholder"
      _output, status = Open3.capture2(env.merge("DOCKER_HOST" => "wrong"), "sh", "bin/prod/docker", "login", "127.0.0.1:5555", "-u", "prosecho", "-p", "fake-placeholder")
      assert_not status.success?
    end
  end

  test "Kamal configuration preserves the remote and internal-only boundaries" do
    require "kamal"
    require "net/ssh"
    config = Kamal::Configuration.create_from(config_file: Pathname.new("config/deploy.yml"), version: SHA)
    assert_equal "2.12.0", Kamal::VERSION
    assert config.builder.git_clone?
    assert_equal "docker", config.builder.driver
    assert_equal 8080, config.proxy.run.http_port
    assert_equal 8443, config.proxy.run.https_port
    assert_equal ["127.0.0.1"], config.proxy.run.bind_ips
    assert_equal "json-file", config.logging.driver
    assert_equal({"max-size" => "10m"}, config.logging.options)
    assert_equal ["--log-driver", '"json-file"'], config.proxy.run.options_args
    assert_equal "10m", config.proxy.run.log_max_size
    assert_equal ["--network", "kamal"], config.accessories.first.network_args
    assert_nil config.accessories.first.port
    assert_equal [ProsechoDeploy::HOST], config.accessories.first.hosts
    assert_equal false, config.ssh.options[:forward_agent]
    document = YAML.load_file("config/deploy.yml")
    assert_equal %w[SECRET_KEY_BASE PGPASSWORD], document.dig("env", "secret")
    assert_equal "postgres", document.dig("accessories", "postgres", "env", "clear", "POSTGRES_USER")
    assert_equal "postgres", document.dig("accessories", "postgres", "env", "clear", "POSTGRES_DB")
    ssh = Net::SSH::Config.for(ProsechoDeploy::HOST, [".devcontainer/ssh.deploy"])
    assert_equal :always, ssh[:verify_host_key]
    assert_equal ["/run/prosecho/known_hosts"], ssh[:user_known_hosts_file]
    assert_equal false, ssh[:forward_agent]
    assert_equal true, ssh[:keys_only]
    assert_equal ["publickey"], ssh[:auth_methods]
  end

  test "accessory admin password is separate from the Rails app password" do
    require "kamal"
    Dir.mktmpdir do |directory|
      sed = File.join(directory, "sed")
      File.write(sed, "#!/bin/sh\ncase \"$*\" in *PGADMINPASSWORD*) printf fake-admin;; *) printf fake-app;; esac\n")
      File.chmod(0o700, sed)
      old_path = ENV["PATH"]
      begin
        ENV["PATH"] = "#{directory}:#{old_path}"
        secrets = Kamal::Secrets.new
        assert_equal "fake-app", secrets["PGPASSWORD"]
        assert_equal "fake-admin", secrets["POSTGRES_PASSWORD"]
        assert_not_equal secrets["PGPASSWORD"], secrets["POSTGRES_PASSWORD"]
      ensure
        ENV["PATH"] = old_path
      end
    end
  end

  test "target lock remains held until the orchestrator closes stdin" do
    Dir.mktmpdir(nil, Dir.home) do |directory|
      FileUtils.mkdir_p(File.join(directory, ".local/share/prosecho"), mode: 0o700)
      {"docker" => "printf /tmp", "df" => "printf unused", "awk" => "printf 8388608"}.each do |name, script|
        path = File.join(directory, name)
        File.write(path, "#!/bin/sh\n#{script}\n")
        File.chmod(0o700, path)
      end
      helper = File.join(directory, "prosecho-cleanup")
      File.write(helper, <<~PYTHON)
        #!/usr/bin/env python3
        import runpy
        module = runpy.run_path(#{File.expand_path("bin/prod/cleanup").inspect})
        module["Cleanup"].__init__.__globals__["STATE"] = module["Path"].home() / ".local/share/prosecho"
        module["Cleanup"].capacity = lambda self: 8 * 1024**3
        module["Path"].read_text = lambda self: "MemAvailable: 8388608 kB\\n"
        module["main"]()
      PYTHON
      File.chmod(0o700, helper)
      env = {"HOME" => directory, "PATH" => "#{directory}:/usr/bin:/bin"}
      file = File.join(directory, ".local/share/prosecho/deploy.lock")
      Open3.popen3(env, "sh", "-c", ProsechoDeploy::LOCK) do |input, output, _error, waiter|
        begin
          assert IO.select([output], nil, nil, 5)
          assert_equal "LOCKED\n", output.gets
          _text, status = Open3.capture2("flock", "-n", file, "true")
          assert_not status.success?
        ensure
          input.close
        end
        assert waiter.value.success?
      end
      _text, status = Open3.capture2("flock", "-n", file, "true")
      assert status.success?
    end
  end

  test "deployment uses the cleanup lock owner without a lock bypass" do
    assert_includes ProsechoDeploy::LOCK, "exec prosecho-cleanup --apply --hold-lock"
    assert_not_includes ProsechoDeploy::LOCK, "exec 9>"
    assert_not_includes ProsechoDeploy::LOCK, "--lock-held"
    source = File.read("bin/prod/deploy")
    assert_includes source, 'if kind == "database" || activation'
    assert_includes source, "JSON.generate(sha: sha, digest: artifact)"
  end

  test "cleanup policies pass hermetic guest CLI regressions" do
    output, error, status = Open3.capture3("ruby", "tests/prodcleanup/cleanup_test.rb")
    assert status.success?, output + error
  end

  test "a switched shared checkout cannot change the isolated checked build source" do
    Dir.mktmpdir do |source|
      runner = ProsechoDeploy::Runner.new
      runner.run("git", "init", source, capture: true)
      File.write(File.join(source, "artifact"), "candidate A\n")
      runner.run("git", "-C", source, "add", "artifact", capture: true)
      runner.run("git", "-C", source, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-m", "A", capture: true)
      first = runner.run("git", "-C", source, "rev-parse", "HEAD", capture: true)
      File.write(File.join(source, "artifact"), "candidate B\n")
      runner.run("git", "-C", source, "add", "artifact", capture: true)
      runner.run("git", "-C", source, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-m", "B", capture: true)
      second = runner.run("git", "-C", source, "rev-parse", "HEAD", capture: true)
      stage = nil
      ProsechoDeploy.with_candidate(source, first) do |candidate_runner|
        stage = Dir.pwd
        assert_equal first, candidate_runner.run("git", "rev-parse", "HEAD", capture: true)
        runner.run("git", "-C", source, "checkout", "--detach", first, capture: true)
        runner.run("git", "-C", source, "checkout", "--detach", second, capture: true)
        assert_equal "candidate A", candidate_runner.run("git", "show", "HEAD:artifact", capture: true)
        assert_equal first, candidate_runner.run("git", "rev-parse", "HEAD", capture: true)
        assert_equal 0, File.stat("artifact").mode & 0o222
        assert_equal 0o700, File.stat(File.dirname(stage)).mode & 0o777
        assert_equal File.join(stage, "bin/prod"), ENV["PATH"].split(":").first
      end
      assert_not File.exist?(stage), "only the operation's own stage is removed"
      assert_equal "candidate B\n", File.read(File.join(source, "artifact"))
    end
  end

  test "lock loss after a capture forbids the next initialization marker mutation" do
    Dir.mktmpdir do |directory|
      reader, writer = IO.pipe
      runner = ProsechoDeploy::Runner.new
      runner.lock = reader
      begin
        assert_equal "query-result", runner.run("ruby", "-e", 'puts "query-result"', capture: true)
        writer.close
        marker = File.join(directory, "initialized")
        assert_raises(ProsechoDeploy::Failure) { runner.run("touch", marker) }
        assert_not File.exist?(marker)
      ensure
        reader.close
        writer.close unless writer.closed?
      end
    end
  end

  test "capture is cancelled on lock loss without exposing command output" do
    reader, writer = IO.pipe
    runner = ProsechoDeploy::Runner.new
    runner.lock = reader
    closer = Thread.new {
      sleep 0.1
      writer.close
    }
    begin
      error = assert_raises(ProsechoDeploy::Failure) do
        runner.run("ruby", "-e", 'STDOUT.puts "fake-credential"; STDERR.puts "fake-credential"; sleep 10', capture: true)
      end
      assert_includes error.message, "lock connection lost"
      assert_not_includes error.message, "fake-credential"
    ensure
      closer.join
      reader.close
    end
  end

  test "command timeout is bounded even when TERM is ignored" do
    Dir.mktmpdir do |directory|
      marker = File.join(directory, "started")
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      assert_raises(ProsechoDeploy::Failure) do
        ProsechoDeploy::Runner.new.run("env", "-u", "RUBYOPT", "ruby", "-e", 'trap("TERM") {}; File.write(ARGV.first, "started"); sleep 10', marker, capture: true, timeout: 0.5)
      end
      assert File.exist?(marker), "child installed its TERM handler before timeout"
      assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - start, :<, 4
    end
  end

  test "bootstrap sends only a validated password in SQL stdin and runs before app authentication" do
    sql = ProsechoDeploy.bootstrap_sql("a" * 64)
    assert_includes sql, "NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS"
    assert_includes sql, "\\gexec"
    assert_includes sql, "log_statement = 'none'"
    assert_raises(ProsechoDeploy::Failure) { ProsechoDeploy.bootstrap_sql("quote'; injection") }
    text = ProsechoDeploy.phases("first", SHA).map { |command| command.join(" ") }
    assert_operator text.index { |command| command.start_with?("bootstrap ") }, :<, text.index { |command| command.start_with?("app-query ") }
    assert text.none? { |command| command.include?("a" * 64) || command.include?("PGADMINPASSWORD") }
    assert_includes text.find { |command| command.start_with?("app-query ") }, "-U prosecho"
    assert_includes text.find { |command| command.start_with?("app-query ") }, "SELECT 1"
    assert_includes text.last, "touch ~/.local/share/prosecho/initialized"
  end

  test "four-key credential file requires distinct bounded hex passwords and filters admin out of Rails stdin" do
    Dir.mktmpdir do |directory|
      file = File.join(directory, "app.env")
      values = {"SECRET_KEY_BASE" => "a" * 64, "PGPASSWORD" => "b" * 64, "PGADMINPASSWORD" => "c" * 64, "KAMAL_REGISTRY_PASSWORD" => "fake-placeholder"}
      File.write(file, values.map { |key, value| "#{key}=#{value}\n" }.join)
      File.chmod(0o600, file)
      secrets = ProsechoDeploy.read_secrets(file)
      rails = ProsechoDeploy.phase_input("database", secrets)
      assert_equal "SECRET_KEY_BASE=#{values["SECRET_KEY_BASE"]}\nPGPASSWORD=#{values["PGPASSWORD"]}\n", rails
      assert_not_includes rails, values["PGADMINPASSWORD"]
      assert_not_includes ProsechoDeploy.phase_input("bootstrap", secrets), values["PGADMINPASSWORD"]
      assert_equal values["PGPASSWORD"] + "\n", ProsechoDeploy.phase_input("app-query", secrets)
      File.write(file, values.merge("PGADMINPASSWORD" => values["PGPASSWORD"]).map { |key, value| "#{key}=#{value}\n" }.join)
      assert_raises(ProsechoDeploy::Failure) { ProsechoDeploy.read_secrets(file) }
      File.chmod(0o644, file)
      assert_raises(ProsechoDeploy::Failure) { ProsechoDeploy.read_secrets(file) }
    end
  end
end
