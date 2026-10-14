require "test_helper"
require "minitest/mock"
require "open3"
require "tmpdir"
load File.expand_path("../../bin/prod/deploy", __dir__) unless defined?(ProsechoDeploy)

class DeploymentTest < ActiveSupport::TestCase
  SHA = "a" * 40

  test "CLI defaults and approvals are invocation scoped and reject obsolete verbs" do
    assert_equal "HEAD", ProsechoDeploy.options([])[:ref]
    %w[HEAD main v1.0 abc1234].each do |ref|
      assert_equal ref, ProsechoDeploy.options([ref])[:ref]
    end
    assert ProsechoDeploy.options(["--allow-migrations"])[:allow_migrations]
    assert_equal "rollback", ProsechoDeploy.options(["rollback", SHA, "--allow-rollback"])[:mode]
    [["first", SHA], ["migrate", SHA], ["rollback"], ["rollback", SHA],
      ["check", "--allow-migrations"], ["install", "--allow-rollback"],
      ["--force"], ["--upload-pack=evil"], ["HEAD", "main"]].each do |args|
      assert_raises(ProsechoDeploy::Failure) { ProsechoDeploy.options(args) }
    end
    ProsechoDeploy::Runner.stub(:new, -> { flunk "Help must not execute commands" }) do
      File.stub(:exist?, false) do
        output, = capture_io { ProsechoDeploy.main(["--help"]) }
        assert_includes output, "Usage:"
      end
    end
  end

  test "check and plan only probe production and check alone runs local tests" do
    [["check", false], ["plan", false], ["deploy", false],
      ["check", true], ["plan", true], ["deploy", true], ["install", true]].each do |mode, low_disk|
      commands = []
      runner = Object.new
      runner.define_singleton_method(:run) do |*command, **options|
        commands << [command, options]
        case command
        when %w[bundle exec kamal version] then "2.12.0"
        when %w[docker --version] then "28.5.2,"
        when %w[docker buildx version] then "v0.29.1 "
        when %w[docker buildx inspect --builder default] then "Driver: docker\nEndpoint: default"
        when %w[docker context inspect default]
          JSON.generate([{Endpoints: {docker: {Host: ProsechoDeploy::DOCKER_HOST}}}])
        when %w[docker buildx imagetools inspect docker.io/docker/dockerfile:1 --raw]
          JSON.generate(schemaVersion: 2, manifests: [{digest: "sha256:" + "b" * 64}])
        when %w[cloudflared --version] then "2026.5.2 "
        when ["ssh", ProsechoDeploy::HOST, ProsechoDeploy::STATUS]
          (mode == "install") ? "new" : "initialized"
        when ["ssh", ProsechoDeploy::HOST, ProsechoDeploy::CAPACITY_METADATA]
          low_disk ? "1024 2097152" : "4194304 2097152"
        when ["ssh", ProsechoDeploy::HOST, ProsechoDeploy::SCHEMA] then ""
        else
          if command.include?("rev-parse")
            SHA
          else
            ((command.last == ProsechoDeploy.artifact_script(SHA)) ? "new" : "")
          end
        end
      end
      candidate = ->(_source, sha, &block) {
        assert_equal SHA, sha
        block.call(runner)
      }
      old_host = ENV["DOCKER_HOST"]
      deployed = []
      begin
        ENV["DOCKER_HOST"] = ProsechoDeploy::DOCKER_HOST
        ProsechoDeploy::Runner.stub(:new, runner) do
          ProsechoDeploy.stub(:with_candidate, candidate) do
            ProsechoDeploy.stub(:verify_identity!, nil) do
              ProsechoDeploy.stub(:clean_sha!, nil) do
                ProsechoDeploy.stub(:read_secrets, {"PGPASSWORD" => "synthetic-password"}) do
                  ProsechoDeploy.stub(:read_rock_key, "synthetic-rock") do
                    File.stub(:exist?, true) do
                      ProsechoDeploy.stub(:deploy, ->(*args, **_flags) { deployed << args.first }) do
                        IO.stub(:popen, ->(*) { flunk "Preflight must not acquire a lock" }) do
                          output, = capture_io do
                            if mode == "deploy" && !low_disk
                              error = assert_raises(ProsechoDeploy::Failure) { ProsechoDeploy.main(["main"]) }
                              assert_includes error.message, "--allow-migrations"
                            elsif mode == "check" && low_disk
                              assert_raises(ProsechoDeploy::Failure) { ProsechoDeploy.main([mode, "main"]) }
                            elsif mode == "deploy"
                              ProsechoDeploy.main(["main", "--allow-migrations"])
                            else
                              ProsechoDeploy.main([mode, "main"])
                            end
                          end
                          assert_not_includes output, "synthetic-password"
                          assert_includes output, "Tests not run" if mode == "plan"
                          assert_includes output, "Capacity: NOT READY" if low_disk
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      ensure
        old_host ? ENV["DOCKER_HOST"] = old_host : ENV.delete("DOCKER_HOST")
      end
      assert_equal((mode == "check" && !low_disk) || (low_disk && %w[deploy install].include?(mode)),
        commands.any? { |command, _| command == ["bin/check"] })
      assert_equal((low_disk && %w[deploy install].include?(mode)) ? [mode] : [], deployed)
      remote = commands.select { |command, _| command.first == "ssh" }
      assert remote.all? { |command, _|
        [ProsechoDeploy::STATUS, ProsechoDeploy::SCHEMA,
          ProsechoDeploy::CAPACITY_METADATA, ProsechoDeploy.artifact_script(SHA)].include?(command.last)
      }
      schema = remote.find { |command, _| command.last == ProsechoDeploy::SCHEMA }
      unless mode == "install"
        assert_equal "synthetic-password\n", schema.last[:input]
        assert schema.last[:capture]
      end
      assert_includes ProsechoDeploy::SCHEMA, "default_transaction_read_only=on"
    end
  end

  test "readiness authenticates schema and rejects implicit installation or downgrade" do
    runner = Object.new
    status = "initialized"
    applied = "20200101000000\n"
    runner.define_singleton_method(:run) do |*command, **_options|
      case command.last
      when ProsechoDeploy::STATUS then status
      when ProsechoDeploy::CAPACITY_METADATA then "4194304 2097152"
      when ProsechoDeploy::SCHEMA then applied
      else "new"
      end
    end
    secrets = {"PGPASSWORD" => "synthetic-password"}
    Dir.stub(:glob, ["db/migrate/20200101000000_old.rb", "db/migrate/20200102000000_new.rb"]) do
      state = ProsechoDeploy.readiness("check", SHA, runner, secrets)
      assert_equal ["db/migrate/20200102000000_new.rb"], state[:pending]
      assert_raises(ProsechoDeploy::Failure) { ProsechoDeploy.readiness("install", SHA, runner, secrets) }
      applied = "20200103000000\n"
      assert_raises(ProsechoDeploy::Failure) { ProsechoDeploy.readiness("deploy", SHA, runner, secrets) }
      status = "new"
      assert_raises(ProsechoDeploy::Failure) { ProsechoDeploy.readiness("deploy", SHA, runner, secrets) }
      assert_not ProsechoDeploy.readiness("plan", SHA, runner, secrets)[:initialized]
    end
  end

  test "migration approval rejects new pending migrations on the locked recheck before build" do
    state = {initialized: true, artifact: "new", pending: ["db/migrate/20200101000000_new.rb"]}
    error = assert_raises(ProsechoDeploy::Failure) { ProsechoDeploy.approve_migrations!(SHA, state, false) }
    assert_includes error.message, SHA
    assert_includes error.message, "--allow-migrations"
    ProsechoDeploy.approve_migrations!(SHA, state, true)
    reader, writer = IO.pipe
    writer.puts "LOCKED"
    writer.flush
    runner = ProsechoDeploy::Runner.new
    begin
      IO.stub(:popen, reader) do
        ProsechoDeploy.stub(:readiness, ->(*) {
          assert_equal reader, runner.lock
          state
        }) do
          ProsechoDeploy.stub(:phases, ->(*) { flunk "Unapproved locked schema must not build" }) do
            reader.stub(:pid, 999999999) do
              assert_raises(ProsechoDeploy::Failure) { ProsechoDeploy.deploy("deploy", SHA, runner, {}) }
            end
          end
        end
      end
      assert_nil runner.lock
    ensure
      reader.close unless reader.closed?
      writer.close
    end
  end

  test "rollback permits newer applied schema but requires retained artifact and no pending schema" do
    commands = []
    artifact = "sha256:" + "b" * 64
    runner = Object.new
    runner.define_singleton_method(:run) do |*command, **_options|
      commands << command
      case command.last
      when ProsechoDeploy::STATUS then "initialized"
      when ProsechoDeploy::CAPACITY_METADATA then "4194304 2097152"
      when ProsechoDeploy::SCHEMA then "20200101000000\n20200102000000\n"
      when ProsechoDeploy.artifact_script(SHA) then artifact
      else ""
      end
    end
    Dir.stub(:glob, ["db/migrate/20200101000000_old.rb"]) do
      state = ProsechoDeploy.readiness("rollback", SHA, runner, {"PGPASSWORD" => "synthetic"})
      assert_empty state[:pending]
      assert commands.any? { |command| command.last == "docker inspect prosecho-web-#{SHA} >/dev/null" }
      artifact = "new"
      assert_raises(ProsechoDeploy::Failure) do
        ProsechoDeploy.readiness("rollback", SHA, runner, {"PGPASSWORD" => "synthetic"})
      end
    end
    artifact = "sha256:" + "b" * 64
    Dir.stub(:glob, ["db/migrate/20200103000000_unapplied.rb"]) do
      assert_raises(ProsechoDeploy::Failure) do
        ProsechoDeploy.readiness("rollback", SHA, runner, {"PGPASSWORD" => "synthetic"})
      end
    end
  end

  test "missing credential files have actionable sanitized failures" do
    %i[read_secrets read_rock_key].each do |method|
      error = assert_raises(ProsechoDeploy::Failure) { ProsechoDeploy.public_send(method, "/nonexistent/private-file") }
      assert_includes error.message, "approved"
      assert_not_includes error.message, "/nonexistent/private-file"
    end
  end

  test "status shell validates markers and tools without creating or changing state" do
    cases = [
      [nil, nil, nil, true, "new"],
      ["initialized", :file, nil, true, "initialized"],
      ["db-prepared", :file, nil, true, "new"],
      *%w[cleanup-inflight cleanup-uncertain].product([:file, :link]).map { |name, kind|
        [name, kind, nil, false, ""]
      },
      *%w[initialized db-prepared].product([:directory, :link]).map { |name, kind|
        [name, kind, nil, false, ""]
      },
      *%w[prosecho-cleanup docker].product([:missing, :failing]).map { |name, kind|
        [nil, nil, [name, kind], false, ""]
      }
    ]
    cases.each do |marker, kind, broken, success, expected|
      Dir.mktmpdir do |directory|
        home = File.join(directory, "home")
        tools = File.join(directory, "tools")
        FileUtils.mkdir_p([home, tools])
        {"prosecho-cleanup" => "--help", "docker" => "info"}.each do |name, arguments|
          next if broken == [name, :missing]
          path = File.join(tools, name)
          script = (broken == [name, :failing]) ? "exit 1" : "test \"$*\" = #{arguments}"
          File.write(path, "#!/bin/sh\n#{script}\n", perm: 0o700)
        end
        if marker
          state = File.join(home, ".local/share/prosecho")
          FileUtils.mkdir_p(state)
          path = File.join(state, marker)
          case kind
          when :file then File.write(path, "")
          when :directory then Dir.mkdir(path)
          when :link then File.symlink("missing-target", path)
          end
        end
        snapshot = -> {
          Dir.glob("#{home}/**/*", File::FNM_DOTMATCH).map { |path|
            stat = File.lstat(path)
            [path, stat.ftype, stat.size, stat.mtime]
          }
        }
        before = snapshot.call
        output, _error, status = Open3.capture3({"HOME" => home, "PATH" => tools},
          "/bin/sh", "-c", ProsechoDeploy::STATUS)
        assert_equal success, status.success?, [marker, kind, broken].inspect
        assert_equal expected, output
        assert_equal before, snapshot.call, "STATUS must not write even an absent state directory"
      end
    end
  end

  test "preflight failures label the gate without exposing captured details" do
    gates = {
      ProsechoDeploy::STATUS => "Production status check failed",
      ProsechoDeploy::CAPACITY_METADATA => "Production capacity metadata check failed",
      ProsechoDeploy::SCHEMA => "App database authentication/schema metadata check failed",
      ProsechoDeploy.artifact_script(SHA) => "Artifact metadata check failed",
      "docker inspect prosecho-web-#{SHA} >/dev/null" => "Retained rollback container check failed"
    }
    gates.each do |failed, label|
      runner = Object.new
      runner.define_singleton_method(:run) do |*command, **_options|
        raise ProsechoDeploy::Failure, "synthetic-secret SQL stderr" if command.last == failed
        case command.last
        when ProsechoDeploy::STATUS then "initialized"
        when ProsechoDeploy::CAPACITY_METADATA then "4194304 2097152"
        when ProsechoDeploy::SCHEMA then ""
        else "sha256:" + "b" * 64
        end
      end
      Dir.stub(:glob, []) do
        error = assert_raises(ProsechoDeploy::Failure) do
          ProsechoDeploy.readiness("rollback", SHA, runner, {"PGPASSWORD" => "synthetic-secret"})
        end
        assert error.message.start_with?(label)
        assert_not_includes error.message, "synthetic-secret"
      end
    end
  end

  test "low memory is fatal and disk must recover before locked deployment phases" do
    capacity = "1024 2097152"
    status = "initialized"
    secrets = {"PGPASSWORD" => "synthetic"}
    runner = Object.new
    runner.define_singleton_method(:run) do |*command, **_options|
      case command.last
      when ProsechoDeploy::STATUS then status
      when ProsechoDeploy::CAPACITY_METADATA then capacity
      when ProsechoDeploy::SCHEMA then ""
      else "new"
      end
    end
    Dir.stub(:glob, []) do
      state = ProsechoDeploy.readiness("deploy", SHA, runner, secrets, allow_disk_recovery: true)
      assert state[:low_disk]
      error = assert_raises(ProsechoDeploy::Failure) { ProsechoDeploy.readiness("deploy", SHA, runner, secrets) }
      assert_includes error.message, "after locked recovery"
      capacity = "4194304 2097152"
      assert_not ProsechoDeploy.readiness("deploy", SHA, runner, secrets)[:low_disk]
      capacity = "4194304 2097151"
      %w[check plan deploy install].each do |mode|
        status = (mode == "install") ? "new" : "initialized"
        error = assert_raises(ProsechoDeploy::Failure) do
          ProsechoDeploy.readiness(mode, SHA, runner, secrets, allow_disk_recovery: true)
        end
        assert_includes error.message, "memory below 2 GiB"
      end
    end
  end

  test "first install waits and prepares once before starting proxy and switching" do
    commands = ProsechoDeploy.phases("install", SHA)
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
    text = ProsechoDeploy.phases("deploy", SHA, migrate: true).map { |command| command.join(" ") }
    assert text.any? { |command| command.include?("db:migrate") }
    assert text.none? { |command| command.match?(/db:prepare|proxy boot|accessory boot|prune/) }
    assert ProsechoDeploy.phases("deploy", SHA).none? { |command| command.join(" ").include?("db:migrate") }
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
    [ProsechoDeploy::LOCK, ProsechoDeploy::STATUS, ProsechoDeploy::CAPACITY_METADATA, ProsechoDeploy::SCHEMA, ProsechoDeploy::DATABASE_WAIT, ProsechoDeploy.artifact_script(SHA), ProsechoDeploy.artifact_script(SHA, record: true), *ProsechoDeploy.phases("install", SHA).select { |command| command.include?("ssh") }.map(&:last)].each do |script|
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

  test "deployment preflight uses the forwarded deployment key without retired credentials" do
    commands = []
    runner = Object.new
    runner.define_singleton_method(:run) do |*command, **_options|
      commands << command
      case command
      when %w[bundle exec kamal version] then "2.12.0"
      when %w[docker --version] then "Docker version 28.5.2,"
      when %w[docker buildx version] then "v0.29.1 "
      when %w[docker buildx inspect --builder default] then "Driver: docker\nEndpoint: default"
      when %w[docker context inspect default]
        JSON.generate([{Endpoints: {docker: {Host: ProsechoDeploy::DOCKER_HOST}}}])
      when %w[docker buildx imagetools inspect docker.io/docker/dockerfile:1 --raw]
        JSON.generate(schemaVersion: 2, manifests: [{digest: "sha256:" + "b" * 64}])
      when %w[cloudflared --version] then "2026.5.2 "
      when %w[ssh-add -L]
        "ssh-ed25519 unrelated-public-key\nssh-ed25519 fake-public-key\n"
      else
        command.include?("rev-parse") ? SHA : " M README.md"
      end
    end
    candidate = ->(_source, _sha, &block) { block.call(runner) }
    secrets = {"PGPASSWORD" => "fake-app-password"}
    deployed = []
    old_env = ENV.to_h.slice("DOCKER_HOST")
    begin
      ENV["DOCKER_HOST"] = ProsechoDeploy::DOCKER_HOST
      state = {initialized: true, artifact: "new", pending: []}
      ProsechoDeploy::Runner.stub(:new, runner) do
        ProsechoDeploy.stub(:with_candidate, candidate) do
          ProsechoDeploy.stub(:clean_sha!, nil) do
            ProsechoDeploy.stub(:read_secrets, secrets) do
              ProsechoDeploy.stub(:read_rock_key, "synthetic-rock-key") do
                ProsechoDeploy.stub(:readiness, state) do
                  ProsechoDeploy.stub(:deploy, ->(*args, **flags) { deployed << [args, flags] }) do
                    original_read = File.method(:read)
                    read = ->(path) {
                      (path == ".devcontainer/production_deploy.pub") ?
                        "ssh-ed25519 fake-public-key\n" : original_read.call(path)
                    }
                    File.stub(:read, read) do
                      File.stub(:stat, ->(path) { flunk "Unexpected credential stat: #{path}" }) do
                        File.stub(:exist?, true) do
                          output, warning = capture_io { ProsechoDeploy.main([]) }
                          assert_includes output, "HEAD"
                          assert_includes warning, "uncommitted changes are excluded"
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
      assert_equal [[["deploy", SHA, runner, secrets], {allow_migrations: false}]], deployed
      resolution = commands.select { |command| command.include?("--end-of-options") }
      assert_equal [["git", "-C", ProsechoDeploy::SOURCE, "rev-parse", "--verify",
        "--end-of-options", "HEAD^{commit}"]], resolution
    ensure
      %w[DOCKER_HOST].each do |key|
        old_env.key?(key) ? ENV[key] = old_env[key] : ENV.delete(key)
      end
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

  test "deployment rejects an agent without the pinned production identity" do
    runner = Object.new
    runner.define_singleton_method(:run) { |*_args, **_options| "ssh-ed25519 unrelated-key\n" }
    File.stub(:read, "ssh-ed25519 pinned-key\n") do
      error = assert_raises(ProsechoDeploy::Failure) { ProsechoDeploy.verify_identity!(runner) }
      assert_includes error.message, "pinned Prosecho deployment key"
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
    assert_equal %w[SECRET_KEY_BASE PGPASSWORD ROCK_API_KEY], document.dig("env", "secret")
    assert_equal "postgres", document.dig("accessories", "postgres", "env", "clear", "POSTGRES_USER")
    assert_equal "postgres", document.dig("accessories", "postgres", "env", "clear", "POSTGRES_DB")
    ssh = Net::SSH::Config.for(ProsechoDeploy::HOST, [".devcontainer/ssh.deploy"])
    assert_equal :always, ssh[:verify_host_key]
    assert_equal ["/run/prosecho/known_hosts"], ssh[:user_known_hosts_file]
    assert_equal false, ssh[:forward_agent]
    assert_equal true, ssh[:keys_only]
    assert_equal ["publickey"], ssh[:auth_methods]
    ordinary = Net::SSH::Config.for(ProsechoDeploy::HOST, [".devcontainer/ssh.prod"])
    assert_equal "ssh-prosecho.menloparking.com", ordinary[:host_name]
    assert_equal :always, ordinary[:verify_host_key]
    assert_equal ["/prosecho/.devcontainer/production_deploy.pub"], ordinary[:keys]
    assert_equal true, ordinary[:keys_only]
    assert_equal false, ordinary[:forward_agent]
  end

  test "Kamal reads app and admin secrets from an explicit external file" do
    require "kamal"
    Dir.mktmpdir do |directory|
      path = File.join(directory, "app.env")
      values = {"KAMAL_REGISTRY_PASSWORD" => "placeholder", "SECRET_KEY_BASE" => "a" * 64,
                "PGPASSWORD" => "b" * 64, "PGADMINPASSWORD" => "c" * 64}
      File.write(path, values.map { |key, value| "#{key}=#{value}\n" }.join, perm: 0o600)
      old_file = ENV["PROSECHO_DEPLOY_SECRETS_FILE"]
      old_rock_file = ENV["PROSECHO_ROCK_API_KEY_FILE"]
      rock_file = File.join(directory, "rock-api-key")
      File.write(rock_file, "synthetic-rock-key\n", perm: 0o600)
      begin
        ENV["PROSECHO_DEPLOY_SECRETS_FILE"] = path
        ENV["PROSECHO_ROCK_API_KEY_FILE"] = rock_file
        assert_equal values, ProsechoDeploy.read_secrets(path)
        secrets = Kamal::Secrets.new
        assert_equal values["PGPASSWORD"], secrets["PGPASSWORD"]
        assert_equal values["PGADMINPASSWORD"], secrets["POSTGRES_PASSWORD"]
        assert_equal values["SECRET_KEY_BASE"], secrets["SECRET_KEY_BASE"]
        assert_equal "synthetic-rock-key", secrets["ROCK_API_KEY"]
        assert_equal values.keys.sort, ProsechoDeploy.read_secrets(path).keys.sort
      ensure
        old_file ? ENV["PROSECHO_DEPLOY_SECRETS_FILE"] = old_file : ENV.delete("PROSECHO_DEPLOY_SECRETS_FILE")
        if old_rock_file
          ENV["PROSECHO_ROCK_API_KEY_FILE"] = old_rock_file
        else
          ENV.delete("PROSECHO_ROCK_API_KEY_FILE")
        end
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
    old_host = ENV["DOCKER_HOST"]
    ENV.delete("DOCKER_HOST")
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
  ensure
    old_host ? ENV["DOCKER_HOST"] = old_host : ENV.delete("DOCKER_HOST")
  end

  test "approved retained rollback skips build inputs and Docker Hub even when registry DNS is offline" do
    old_host = ENV["DOCKER_HOST"]
    ENV["DOCKER_HOST"] = ProsechoDeploy::DOCKER_HOST
    commands = []
    runner = Object.new
    runner.define_singleton_method(:run) do |*command, **_options|
      commands << command
      case command
      when %w[bundle exec kamal version] then "2.12.0"
      when %w[docker --version] then "28.5.2,"
      when %w[docker buildx version] then "v0.29.1 "
      when %w[cloudflared --version] then "2026.5.2 "
      when ["ssh", ProsechoDeploy::HOST, ProsechoDeploy::STATUS] then "initialized"
      when ["ssh", ProsechoDeploy::HOST, ProsechoDeploy::CAPACITY_METADATA] then "4194304 2097152"
      when ["ssh", ProsechoDeploy::HOST, ProsechoDeploy::SCHEMA] then ""
      when ["ssh", ProsechoDeploy::HOST, ProsechoDeploy.artifact_script(SHA)] then "sha256:" + "b" * 64
      when ["ssh", ProsechoDeploy::HOST, "docker inspect prosecho-web-#{SHA} >/dev/null"] then ""
      when ["bin/check"] then ""
      else
        raise ProsechoDeploy::Failure, "Docker Hub DNS unavailable" if command.first == "docker"
        raise "Unexpected command" unless command.first == "git"
        command.include?("rev-parse") ? SHA : ""
      end
    end
    candidate = ->(_source, _sha, &block) { block.call(runner) }
    deployed = []
    ProsechoDeploy::Runner.stub(:new, runner) do
      ProsechoDeploy.stub(:with_candidate, candidate) do
        ProsechoDeploy.stub(:verify_identity!, ->(*) { commands << ["agent-gate"] }) do
          ProsechoDeploy.stub(:read_secrets, {"PGPASSWORD" => "synthetic-password"}) do
            ProsechoDeploy.stub(:read_rock_key, "synthetic-rock") do
              ProsechoDeploy.stub(:public_frontend_ref, -> { flunk "Rollback must not read build inputs" }) do
                ProsechoDeploy.stub(:deploy, ->(mode, *) { deployed << mode }) do
                  File.stub(:exist?, true) do
                    Dir.stub(:glob, []) do
                      capture_io { ProsechoDeploy.main(["rollback", SHA, "--allow-rollback"]) }
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
    assert_equal ["rollback"], deployed
    assert_equal [%w[docker --version], %w[docker buildx version]],
      commands.select { |command| command.first == "docker" }
    assert_includes commands, ["agent-gate"]
    [ProsechoDeploy::STATUS, ProsechoDeploy::CAPACITY_METADATA, ProsechoDeploy::SCHEMA,
      ProsechoDeploy.artifact_script(SHA), "docker inspect prosecho-web-#{SHA} >/dev/null"].each do |script|
      assert_includes commands, ["ssh", ProsechoDeploy::HOST, script]
    end
    assert_includes commands, ["bin/check"]
  ensure
    old_host ? ENV["DOCKER_HOST"] = old_host : ENV.delete("DOCKER_HOST")
  end

  test "public Dockerfile contract recognizes tabs and rejects hidden private stages or ARG overrides" do
    dockerfile = File.read("Dockerfile")
    ruby_version = File.read(".ruby-version")
    source = dockerfile
    read = ->(path) { (path == "Dockerfile") ? source : ruby_version }
    File.stub(:read, read) do
      assert_equal "docker.io/docker/dockerfile:1", ProsechoDeploy.public_frontend_ref
      source = dockerfile.gsub(/^FROM /, "FROM\t").sub(/^ARG /, "ARG\t")
      assert_equal "docker.io/docker/dockerfile:1", ProsechoDeploy.public_frontend_ref
      ["FROM\tprivate.example/final:1\n", "ARG\tRUBY_VERSION=9.9.9\n",
        "FROM base # unsupported inline comment\n"].each do |extra|
        source = dockerfile + extra
        assert_raises(ProsechoDeploy::Failure) { ProsechoDeploy.public_frontend_ref }
      end
      source = dockerfile + "FROM\tprivate.example/final:1\n"
      runner = Object.new
      runner.define_singleton_method(:run) { |*| flunk "Invalid public inputs must fail before probes" }
      assert_raises(ProsechoDeploy::Failure) { ProsechoDeploy.build_preflight(runner) }
      source = dockerfile + "# FROM\tprivate.example/not-an-instruction:1\n"
      assert_equal "docker.io/docker/dockerfile:1", ProsechoDeploy.public_frontend_ref
    end
  end

  test "candidate Docker config bypasses broken helpers and restores caller scope on every exit" do
    old_env = ENV.to_h.slice(*ProsechoDeploy::OPERATION_ENV)
    runner = ProsechoDeploy::Runner.new
    sha = runner.run("git", "-C", ProsechoDeploy::SOURCE, "rev-parse", "HEAD", capture: true)
    Dir.mktmpdir do |directory|
      caller_config = File.join(directory, "caller")
      Dir.mkdir(caller_config, 0o700)
      config_file = File.join(caller_config, "config.json")
      contents = JSON.generate(credsStore: "broken", auths: {}, currentContext: "wrong")
      File.write(config_file, contents, perm: 0o600)
      File.write(File.join(directory, "docker-credential-broken"), "#!/bin/sh\nexit 255\n", perm: 0o700)
      docker = File.join(directory, "docker")
      File.write(docker, <<~RUBY, perm: 0o700)
        #!/usr/bin/env ruby
        require "json"
        config = JSON.parse(File.read(File.join(ENV.fetch("DOCKER_CONFIG"), "config.json")))
        exec("docker-credential-" + config["credsStore"]) if config["credsStore"]
        abort "wrong route" unless ENV["DOCKER_HOST"] == #{ProsechoDeploy::DOCKER_HOST.inspect}
        abort "inherited override" if %w[DOCKER_CONTEXT BUILDX_CONFIG BUILDX_BUILDER].any? { |key| ENV.key?(key) }
        puts "public-metadata"
      RUBY
      ENV["PATH"] = "#{directory}:#{ENV.fetch("PATH")}"
      ENV["DOCKER_CONFIG"] = caller_config
      ENV.delete("DOCKER_HOST")
      %w[DOCKER_CONTEXT BUILDX_CONFIG BUILDX_BUILDER].each { |key| ENV[key] = "caller-override" }
      assert_raises(ProsechoDeploy::Failure) { runner.run(docker, capture: true) }
      caller_env = ENV.to_h.slice(*ProsechoDeploy::OPERATION_ENV)
      [:success, :failure, :timeout].each do |exit_kind|
        operation = nil
        exercise = -> {
          ProsechoDeploy.with_candidate(ProsechoDeploy::SOURCE, sha) do |candidate_runner|
            operation = ENV.fetch("TMPDIR")
            private_config = ENV.fetch("DOCKER_CONFIG")
            assert_equal 0o700, File.stat(private_config).mode & 0o777
            assert_equal 0o600, File.stat(File.join(private_config, "config.json")).mode & 0o777
            assert_equal({}, JSON.parse(File.read(File.join(private_config, "config.json"))))
            assert_equal "public-metadata", candidate_runner.run(docker, capture: true)
            ProsechoDeploy.with_candidate(ProsechoDeploy::SOURCE, sha) do
              assert_not_equal private_config, ENV["DOCKER_CONFIG"]
            end
            assert_equal private_config, ENV["DOCKER_CONFIG"]
            raise ProsechoDeploy::Failure, "synthetic failure" if exit_kind == :failure
            candidate_runner.run("sleep", "10", capture: true, timeout: 0.05) if exit_kind == :timeout
          end
        }
        (exit_kind == :success) ? exercise.call : assert_raises(ProsechoDeploy::Failure, &exercise)
        assert_equal caller_env, ENV.to_h.slice(*ProsechoDeploy::OPERATION_ENV)
        assert_equal contents, File.read(config_file)
        assert_not File.exist?(operation)
      end
    end
  ensure
    ProsechoDeploy::OPERATION_ENV.each { |key| old_env.key?(key) ? ENV[key] = old_env[key] : ENV.delete(key) }
  end

  test "wrong explicit Docker host is rejected before any candidate or target command" do
    old_host = ENV["DOCKER_HOST"]
    ENV["DOCKER_HOST"] = "ssh://wrong-target"
    ProsechoDeploy::Runner.stub(:new, -> { flunk "Wrong host must not start commands" }) do
      error = assert_raises(ProsechoDeploy::Failure) do
        ProsechoDeploy.with_candidate(ProsechoDeploy::SOURCE, SHA) { flunk "Wrong host must not yield" }
      end
      assert_includes error.message, "pinned Prosecho SSH alias"
      assert_equal "ssh://wrong-target", ENV["DOCKER_HOST"]
    end
  ensure
    old_host ? ENV["DOCKER_HOST"] = old_host : ENV.delete("DOCKER_HOST")
  end

  test "build preflight validates public source and labels bounded read-only metadata failures" do
    commands = []
    broken = nil
    endpoint = ProsechoDeploy::DOCKER_HOST
    metadata = JSON.generate(schemaVersion: 2, manifests: [{digest: "sha256:" + "b" * 64}])
    runner = Object.new
    runner.define_singleton_method(:run) do |*command, **options|
      commands << command
      raise "Unbounded probe" unless options == {capture: true, timeout: 30}
      raise ProsechoDeploy::Failure, "synthetic-secret" if command.include?(broken)
      case command
      when %w[docker buildx inspect --builder default] then "Driver: docker\nEndpoint: default"
      when %w[docker context inspect default]
        JSON.generate([{Endpoints: {docker: {Host: endpoint}}}])
      else metadata
      end
    end
    output, = capture_io { ProsechoDeploy.build_preflight(runner) }
    assert_includes output, "public frontend metadata resolved"
    assert_equal [%w[docker buildx inspect --builder default], %w[docker context inspect default],
      %w[docker buildx imagetools inspect docker.io/docker/dockerfile:1 --raw]], commands
    {"buildx" => "Default builder endpoint/driver", "imagetools" => "Public Dockerfile frontend"}.each do |failure, label|
      broken = failure
      error = assert_raises(ProsechoDeploy::Failure) { ProsechoDeploy.build_preflight(runner) }
      assert_includes error.message, label
      assert_not_includes error.message, "synthetic-secret"
    end
    broken = nil
    endpoint = "ssh://wrong-target"
    assert_raises(ProsechoDeploy::Failure) { ProsechoDeploy.build_preflight(runner) }
    endpoint = ProsechoDeploy::DOCKER_HOST
    metadata = JSON.generate(schemaVersion: 2, manifests: "invalid-type")
    assert_raises(ProsechoDeploy::Failure) { ProsechoDeploy.build_preflight(runner) }
    metadata = "invalid-json synthetic-secret"
    error = assert_raises(ProsechoDeploy::Failure) { ProsechoDeploy.build_preflight(runner) }
    assert_not_includes error.message, "synthetic-secret"
    File.stub(:read, "# syntax=private.example/frontend:1\n") do
      assert_raises(ProsechoDeploy::Failure) { ProsechoDeploy.public_frontend_ref }
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
    text = ProsechoDeploy.phases("install", SHA).map { |command| command.join(" ") }
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

  test "dedicated Rock key file requires private permissions and never reflects invalid values" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "rock-api-key")
      File.write(path, "synthetic-rock/key+with=characters\n", perm: 0o600)
      assert_equal "synthetic-rock/key+with=characters", ProsechoDeploy.read_rock_key(path)
      link = File.join(directory, "linked-key")
      File.symlink(path, link)
      assert_raises(ProsechoDeploy::Failure) { ProsechoDeploy.read_rock_key(link) }
      File.chmod(0o644, path)
      assert_raises(ProsechoDeploy::Failure) { ProsechoDeploy.read_rock_key(path) }
      File.chmod(0o600, path)
      File.write(path, "synthetic-private-key\nsecond-line")
      error = assert_raises(ProsechoDeploy::Failure) { ProsechoDeploy.read_rock_key(path) }
      assert_not_includes error.message, "synthetic-private-key"
      File.write(path, "")
      assert_raises(ProsechoDeploy::Failure) { ProsechoDeploy.read_rock_key(path) }
      File.binwrite(path, "synthetic-private-\xFF")
      assert_raises(ProsechoDeploy::Failure) { ProsechoDeploy.read_rock_key(path) }
      File.write(path, "x" * 4097)
      assert_raises(ProsechoDeploy::Failure) { ProsechoDeploy.read_rock_key(path) }
    end
  end
end
