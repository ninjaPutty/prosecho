require "json"
require "minitest/autorun"
require "open3"
require "tmpdir"
require "yaml"

class DeveloperSshTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("prosecho-developer-ssh-")
    @socket = File.join(@dir, "agent.sock")
    @agent = Process.spawn("ssh-agent", "-D", "-a", @socket, out: File::NULL, err: File::NULL)
    100.times do
      break if File.socket?(@socket)
      sleep 0.02
    end
    assert File.socket?(@socket), "temporary isolated agent did not start"
    @env = {"SSH_AUTH_SOCK" => @socket}
  end

  def teardown
    Process.kill("TERM", @agent)
    Process.wait(@agent)
    FileUtils.remove_entry(@dir)
  end

  def test_default_and_overlay_boundary
    config = JSON.parse(File.read(".devcontainer/devcontainer.json"))
    assert_equal ["compose.yaml", "compose.runtime.yaml"], config.fetch("dockerComposeFile")
    assert_equal true, config.dig("customizations", "vscode", "settings",
      "dev.containers.forwardSSHAgent")
    app = YAML.load_file(".devcontainer/compose.yaml").fetch("services").fetch("app")
    refute app.fetch("environment").key?("SSH_AUTH_SOCK")
    overlay = YAML.load_file(".devcontainer/compose.developer-ssh.yaml").fetch("services")
    assert_equal ["app"], overlay.keys
    mount = overlay.fetch("app").fetch("volumes").fetch(0)
    assert_equal false, mount.dig("bind", "create_host_path")
    assert_equal true, mount.fetch("read_only")
    assert_includes mount.fetch("source"), "PROSECHO_DEV_SSH_AGENT_SOCK:?"
  end

  def test_doctor_agent_gates
    _, error, status = run_script("developer-ssh-doctor.sh", env: {"SSH_AUTH_SOCK" => nil})
    assert_equal 2, status.exitstatus
    assert_includes error, "No developer agent socket"
    _, error, status = run_script("developer-ssh-doctor.sh")
    assert_equal 2, status.exitstatus
    assert_includes error, "empty or inaccessible"
    _, _, status = run_script("developer-ssh-doctor.sh", env: {"SSH_AUTH_SOCK" => "/missing"})
    assert_equal 2, status.exitstatus
    stub("ssh-add", "exit 2")
    _, error, status = run_script("developer-ssh-doctor.sh", env: stub_env)
    assert_equal 2, status.exitstatus
    assert_includes error, "empty or inaccessible"
  end

  def test_doctor_github_exit_status
    stub("ssh-add", "exit 0")
    stub("ssh", 'printf "%s\\n" "Hi fixture! successfully authenticated, but GitHub does not provide shell access."; exit 1')
    _, _, status = run_script("developer-ssh-doctor.sh", "--github", env: stub_env)
    assert status.success?
    stub("ssh", 'printf "%s\\n" "Permission denied (publickey)."; exit 255')
    _, error, status = run_script("developer-ssh-doctor.sh", "--github", env: stub_env)
    assert_equal 1, status.exitstatus
    assert_includes error, "not confirmed"
    stub("ssh", 'printf "%s\\n" "unrecognized response"; exit 1')
    _, _, status = run_script("developer-ssh-doctor.sh", "--github", env: stub_env)
    refute status.success?
  end

  def test_git_wrapper_selection_and_missing_socket
    stub("ssh", 'printf "%s\\n" "$@"')
    output, _, status = run_script("git-ssh.sh", "git@github.com", "git-upload-pack 'a/b'",
      env: stub_env)
    assert status.success?
    assert_equal ["-F", "/prosecho/.devcontainer/ssh.git", "git@github.com",
      "git-upload-pack 'a/b'"], output.lines.map(&:chomp)
    public_key = File.join(@dir, "selected.pub")
    File.write(public_key, "fixture public identity")
    output, _, status = run_script("git-ssh.sh", "git@github.com",
      env: stub_env.merge("PROSECHO_DEV_SSH_PUBLIC_KEY" => public_key))
    assert status.success?
    assert_includes output, "IdentitiesOnly=yes\n-i\n#{public_key}\n"
    _, _, status = run_script("git-ssh.sh", env: {"SSH_AUTH_SOCK" => nil})
    assert_equal 2, status.exitstatus
    _, _, status = run_script("git-ssh.sh",
      env: {"PROSECHO_DEV_SSH_PUBLIC_KEY" => "/missing.pub"})
    assert_equal 2, status.exitstatus
  end

  def test_strict_github_trust
    output, error, status = Open3.capture3("ssh", "-G", "-F", ".devcontainer/ssh.git",
      "github.com")
    assert status.success?, error
    %w[batchmode\ yes forwardagent\ no stricthostkeychecking\ true identityfile\ none
      hostname\ github.com user\ git hostkeyalgorithms\ ssh-ed25519].each do |setting|
      assert_includes output, "#{setting}\n"
    end
    refute_includes output, "proxycommand false"
    output, _, status = Open3.capture3("ssh", "-G", "-F", ".devcontainer/ssh.git", "other.example")
    assert status.success?
    assert_includes output, "proxycommand false\n"
    output, _, status = Open3.capture3("ssh-keygen", "-lf", ".devcontainer/git_github_known_hosts")
    assert status.success?
    assert_includes output, "SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU"
  end

  private

  def run_script(name, *args, env: {})
    Open3.capture3(@env.merge(env), "sh", ".devcontainer/#{name}", *args)
  end

  def stub(name, body)
    path = File.join(@dir, name)
    File.write(path, "#!/bin/sh\n#{body}\n")
    File.chmod(0o700, path)
  end

  def stub_env
    {"PATH" => "#{@dir}:#{ENV.fetch("PATH")}"}
  end
end
