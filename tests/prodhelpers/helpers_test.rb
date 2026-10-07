require "json"
require "minitest/autorun"
require "open3"
require "tmpdir"

class ProductionHelpersTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  ID = "b" * 64
  ROW = "#{ID} prosecho-web-#{"a" * 40}\n"

  def setup
    @directory = Dir.mktmpdir
    @log = File.join(@directory, "calls.jsonl")
    ssh = File.join(@directory, "ssh")
    File.write(ssh, <<~RUBY)
      #!/usr/bin/env ruby
      require "json"
      query = ARGV.last.include?("container ls")
      File.open(ENV.fetch("CALL_LOG"), "a") do |file|
        file.puts JSON.generate(args: ARGV, input: query ? nil : STDIN.read)
      end
      puts ENV.fetch("CONTAINERS") if query
      exit(query ? Integer(ENV.fetch("QUERY_STATUS", "0")) : 23)
    RUBY
    File.chmod(0o700, ssh)
    @env = {"DOCKER_HOST" => nil, "PATH" => "#{@directory}:#{ENV.fetch("PATH")}",
            "CALL_LOG" => @log, "CONTAINERS" => ROW}
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_console_and_shell_allocate_terminal_and_preserve_exit_status
    {"console" => "bin/rails console -e production --sandbox", "shell" => "sh"}.each do |name, command|
      args = (name == "console") ? ["--sandbox"] : []
      _out, error, status = invoke(name, *args)
      assert_equal 23, status.exitstatus, error
      call = calls.last.fetch("args")
      assert_includes call, "-tt"
      assert_equal "docker exec -it #{ID} #{command}", call.last
      assert_includes call, File.join(ROOT, ".devcontainer/ssh.prod")
      assert_includes call, "ssh-prosecho.menloparking.com"
      assert_includes call, "ConnectTimeout=10"
    end
  end

  def test_deployment_container_keeps_its_dedicated_connection
    @env["DOCKER_HOST"] = "ssh://deploy@prosecho-deploy-cloudflare"
    _out, error, status = invoke("runner", "puts 1")
    assert_equal 23, status.exitstatus, error
    assert_includes calls.last.fetch("args"), File.join(ROOT, ".devcontainer/ssh.deploy")
    assert_includes calls.last.fetch("args"), "prosecho-deploy-cloudflare"
    assert_includes calls.last.fetch("args"), "ConnectTimeout=10"
  end

  def test_cloudflare_developer_connection_needs_no_runtime_env_or_token
    cloudflared = File.join(@directory, "cloudflared")
    File.write(cloudflared, <<~SH)
      #!/bin/sh
      test -z "${TUNNEL_SERVICE_TOKEN_ID+set}" || exit 1
      test -z "${TUNNEL_SERVICE_TOKEN_SECRET+set}" || exit 1
      printf '%s\\n' "$@"
    SH
    File.chmod(0o700, cloudflared)
    env = @env.merge("CF_SSH_HOST" => nil, "PROSECHO_CF_AUTH" => nil,
      "TUNNEL_SERVICE_TOKEN_ID" => "ignored", "TUNNEL_SERVICE_TOKEN_SECRET" => "ignored")
    output, error, status = Open3.capture3(env, "sh", File.join(ROOT, "bin/prod/cloudflare-ssh"))
    assert status.success?, error
    assert_equal "access\nssh\n--hostname\nssh-prosecho.menloparking.com\n", output
  end

  def test_cloudflare_ignores_legacy_auth_modes_and_never_loads_access_credentials
    scripts = {
      "stat" => "exit 99",
      "jq" => "exit 99",
      "cloudflared" => <<~SH
        test -z "${TUNNEL_SERVICE_TOKEN_ID+set}"
        test -z "${TUNNEL_SERVICE_TOKEN_SECRET+set}"
        printf '%s\\n' "$*"
      SH
    }
    scripts.each do |name, content|
      path = File.join(@directory, name)
      File.write(path, "#!/bin/sh\nset -eu\n#{content}\n")
      File.chmod(0o700, path)
    end
    ["browser", "service-token", "invalid"].each do |mode|
      env = @env.merge("CF_SSH_HOST" => "fake.example", "PROSECHO_CF_AUTH" => mode,
        "TUNNEL_SERVICE_TOKEN_ID" => "ignored", "TUNNEL_SERVICE_TOKEN_SECRET" => "ignored")
      output, error, status = Open3.capture3(env, "sh", File.join(ROOT, "bin/prod/cloudflare-ssh"))
      assert status.success?, error
      assert_empty error
      assert_equal "access ssh --hostname fake.example\n", output
    end
  end

  def test_cloudflare_missing_binary_has_actionable_error_without_credentials
    env = @env.merge("PATH" => @directory,
      "TUNNEL_SERVICE_TOKEN_ID" => "ignored", "TUNNEL_SERVICE_TOKEN_SECRET" => "ignored")
    output, error, status = Open3.capture3(env, "/bin/sh", File.join(ROOT, "bin/prod/cloudflare-ssh"))
    refute status.success?
    assert_empty output
    assert_equal "cloudflared is missing; rebuild the Prosecho devcontainer image.\n", error
  end

  def test_ssh_configs_keep_strict_pins_and_plain_proxy_without_connecting
    {"prod" => "ssh-prosecho.menloparking.com", "deploy" => "prosecho-deploy-cloudflare"}
      .each do |mode, host|
      output, error, status = Open3.capture3("ssh", "-G", "-F",
        File.join(ROOT, ".devcontainer/ssh.#{mode}"), host)
      assert status.success?, error
      assert_includes output, "proxycommand cloudflare-ssh\n"
      assert_includes output, "stricthostkeychecking true\n"
      assert_includes output, "globalknownhostsfile /dev/null\n"
      assert_includes output, "forwardagent no\n"
      pin = (mode == "prod") ? "/prosecho/.devcontainer/production_known_hosts" : "/run/prosecho/known_hosts"
      assert_includes output, "userknownhostsfile #{pin}\n"
      if mode == "deploy"
        assert_includes output, "identityagent /run/prosecho/agent.sock\n"
        assert_includes output, "identityfile /run/prosecho/deploy.pub\n"
        assert_includes output, "identitiesonly yes\n"
      end
    end
    output, error, status = Open3.capture3("ssh-keygen", "-lf",
      File.join(ROOT, ".devcontainer/production_known_hosts"))
    assert status.success?, error
    assert_includes output, "SHA256:pL/Z+zpE+W25Q56uyJk7Z0+wtjvG2zOdkZm7UX7VyCw"
  end

  def test_inline_ruby_is_quoted_as_one_remote_argument
    code = %q{puts "it's $(touch /tmp/nope); safe"}
    _out, error, status = invoke("runner", code, "two words")
    assert_equal 23, status.exitstatus, error
    require "shellwords"
    assert_equal ["docker", "exec", "-i", ID, "bin/rails", "runner", "-e", "production",
      code, "two words"], Shellwords.split(calls.last.fetch("args").last)
    assert_includes calls.last.fetch("args"), "-T"
  end

  def test_local_file_is_streamed_without_upload_and_arguments_are_forwarded
    file = File.join(@directory, "ruby file.rb")
    code = "puts ARGV.inspect\nputs 'local content'\n"
    File.write(file, code)
    _out, error, status = invoke("runner", file, "two words")
    assert_equal 23, status.exitstatus, error
    assert_equal code, calls.last.fetch("input")
    assert_match(/runner -e production - two\\ words\z/, calls.last.fetch("args").last)
  end

  def test_stdin_runner
    _out, error, status = invoke("runner", "-", input: "puts 123\n")
    assert_equal 23, status.exitstatus, error
    assert_equal "puts 123\n", calls.last.fetch("input")
  end

  def test_missing_or_ambiguous_app_and_failed_discovery_do_not_execute
    ["", ROW + ROW, "bad-id prosecho-web-#{"a" * 40}\n"].each do |rows|
      @env["CONTAINERS"] = rows
      previous = calls.size
      _out, _error, status = invoke("runner", "puts 1")
      refute status.success?
      assert_equal previous + 1, calls.size
    end
    @env["CONTAINERS"] = ROW
    @env["QUERY_STATUS"] = "1"
    previous = calls.size
    _out, _error, status = invoke("runner", "puts 1")
    refute status.success?
    assert_equal previous + 1, calls.size
  end

  def test_runner_requires_input_before_connecting
    _out, error, status = invoke("runner")
    refute status.success?
    assert_includes error, "Usage:"
    assert_empty calls
  end

  def test_ssh_opens_host_session_without_container_discovery_even_with_helpers_on_path
    @env["PATH"] = "#{ROOT}/bin/prod:#{@env.fetch("PATH")}"
    _out, error, status = invoke("ssh")
    assert_equal 23, status.exitstatus, error
    assert_equal 1, calls.size
    args = calls.last.fetch("args")
    assert_equal "ssh-prosecho.menloparking.com", args.last
    assert_includes args, "-tt"
    assert_includes args, File.join(ROOT, ".devcontainer/ssh.prod")
  end

  def test_ssh_path_wrapper_preserves_ordinary_client_calls_without_connecting
    output, error, status = invoke("ssh", "-G", "-F", File::NULL, "fake.example")
    assert status.success?, error
    assert_includes output, "hostname fake.example"
    assert_empty calls
  end

  private

  def calls
    File.exist?(@log) ? File.readlines(@log).map { |line| JSON.parse(line) } : []
  end

  def invoke(name, *args, input: "")
    Open3.capture3(@env, "sh", File.join(ROOT, "bin/prod", name), *args,
      stdin_data: input, chdir: @directory)
  end
end
