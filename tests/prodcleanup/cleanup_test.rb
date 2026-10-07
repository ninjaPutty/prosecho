require "minitest/autorun"
require "open3"
require "tmpdir"
require "fileutils"
require "json"
require "time"

class ProductionCleanupTest < Minitest::Test
  SCRIPT = File.expand_path("../../bin/prod/cleanup", __dir__)
  REPO = "127.0.0.1:5555/prosecho"
  INITIAL = %w[4a69a6aeca31d6f75f8496bb38f0a90abbb5a74b 66870ed7351e11ecf1f720743c54fd3bd25bed96 c9989afa5b16ee745feb920efde7137e598e27cb]

  def setup
    @directory = Dir.mktmpdir(nil, Dir.home)
    @state = File.join(@directory, ".local/share/prosecho")
    FileUtils.mkdir_p(@state)
    File.chmod(0o700, @state)
    File.write(File.join(@state, "protect.json"), JSON.generate(INITIAL))
    @old = "a" * 40
    @digest = "sha256:" + "b" * 64
    @records = [@old, "c" * 40, "d" * 40, "e" * 40].each_with_index.map { |sha, i| {sha: sha, digest: @digest, at: Time.now.to_i - 900_000 + i} }
    @containers = [container(@old)]
    fake = File.join(@directory, "docker")
    File.write(fake, <<~RUBY)
      #!#{RbConfig.ruby}
      require "json"
      args = ARGV.drop(2)
      File.open(ENV.fetch("COMMAND_LOG"), "a") { |f| f.puts JSON.generate(args) }
      data = JSON.parse(File.read(ENV.fetch("DOCKER_FIXTURE")))
      case args.first(2)
      when ["info", "--format"] then puts ENV.fetch("HOME")
      when ["buildx", "du"] then data.fetch("cache").each { |row| puts JSON.generate(row) }
      when ["buildx", "prune"]
        abort "unexpected prune arguments" unless args == ["buildx", "prune", "--builder", "default", "--filter", "until=168h", "--max-used-space", "5368709120", "--force"]
        abort "fake prune failure" if data["prune_failure"]
        if data["fork_plugin"]
          fork do
            trap("TERM", "IGNORE")
            Dir.children("/proc/self/fd").map(&:to_i).select { |fd| fd > 2 }.each { |fd| IO.for_fd(fd).close rescue nil }
            STDOUT.close
            STDERR.close
            File.write(ENV.fetch("PLUGIN_PID"), Process.pid.to_s)
            loop { sleep 1 }
          end
          sleep 20
        end
        # Model the server's dangerous NULL-until behavior, even above the target budget.
        data["cache"].reject! { |r| r["Reclaimable"] && (!r["LastUsedAt"] || r["ID"] == "old-cache") }
        File.write(ENV.fetch("DOCKER_FIXTURE"), JSON.generate(data))
      when ["container", "ls"]
        data["inventory_calls"] = data.fetch("inventory_calls", 0) + 1
        if data["start_other_on_recheck"] && data["inventory_calls"] > 1
          data["containers"].last["State"] = {"Running" => true, "Status" => "running"}
        end
        File.write(ENV.fetch("DOCKER_FIXTURE"), JSON.generate(data))
        puts data.fetch("containers").map { |c| c.fetch("Id") }
      when ["container", "inspect"]
        c = data.fetch("containers").find { |c| c.fetch("Id") == args.last || c.fetch("Name") == "/" + args.last }
        abort "missing container" unless c
        if data["restart"]
          c["State"] = {"Running" => true, "Status" => "running"}
        end
        puts JSON.generate([c])
      when ["container", "rm"]
        data["containers"].reject! { |c| c["Id"] == args.last }
        File.write(ENV.fetch("DOCKER_FIXTURE"), JSON.generate(data))
      when ["image", "ls"] then puts data.fetch("images").keys
      when ["image", "inspect"]
        image = data.fetch("images")[args.last] || data.fetch("images").values.find { |i| i["Id"] == args.last }
        abort "missing image" unless image
        puts JSON.generate([image])
      when ["image", "rm"]
        unless args.length == 4 && args[2] == "--no-prune" && data["images"].key?(args.last)
          data["implicit_parent_removed"] = true
          File.write(ENV.fetch("DOCKER_FIXTURE"), JSON.generate(data))
          abort "implicit parent removal or unexpected image rm command"
        end
        data["images"].delete(args.last)
        File.write(ENV.fetch("DOCKER_FIXTURE"), JSON.generate(data))
      else abort "unexpected Docker command"
      end
    RUBY
    File.chmod(0o700, fake)
    @fixture = {containers: @containers, images: {"#{REPO}:#{@old}" => {"Id" => "sha256:" + "f" * 64, "RepoDigests" => ["#{REPO}@#{@digest}"]}}, cache: [{"ID" => "old-cache", "Reclaimable" => true, "LastUsedAt" => (Time.now - 900_000).utc.iso8601}], parents: ["retained-parent"]}
    @env = {"HOME" => @directory, "PATH" => "#{@directory}:#{ENV.fetch("PATH")}", "RUBYOPT" => nil, "DOCKER_FIXTURE" => File.join(@directory, "fixture.json"), "COMMAND_LOG" => File.join(@directory, "commands.jsonl")}
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def commands
    File.readlines(@env.fetch("COMMAND_LOG")).map { |line| JSON.parse(line) }
  end

  def container(sha, id: "1" * 64, running: false)
    {"Id" => id, "Name" => "/prosecho-web-#{sha}", "Image" => "sha256:" + "f" * 64, "Config" => {"Image" => "#{REPO}:#{sha}", "Labels" => {"service" => "prosecho", "role" => "web"}}, "State" => {"Status" => running ? "running" : "exited", "Running" => running, "FinishedAt" => (Time.now - 900_000).utc.iso8601}}
  end

  def run_cleanup(*args)
    File.write(@env.fetch("DOCKER_FIXTURE"), JSON.generate(@fixture))
    File.write(File.join(@state, "success.json"), JSON.generate(@records, allow_nan: true))
    harness = <<~PYTHON
      import runpy, sys
      module = runpy.run_path(sys.argv.pop(1))
      module['Cleanup'].__init__.__globals__['STATE'] = module['Path'].home() / '.local/share/prosecho'
      if module['os'].environ.get('TEST_DOCKER_TIMEOUT'):
          module['Cleanup'].docker.__globals__['DOCKER_TIMEOUT'] = float(module['os'].environ['TEST_DOCKER_TIMEOUT'])
      sys.exit(module['main']())
    PYTHON
    Open3.capture3(@env, "python3", "-c", harness, SCRIPT, *args)
  end

  def test_cache_failure_aborts_without_release_mutations
    @fixture[:prune_failure] = true
    _out, _err, status = run_cleanup("--apply")
    refute status.success?
    refute commands.any? { |c| c[1] == "rm" }
  end

  def test_dry_run_reports_age_from_metadata_and_never_mutates
    @fixture[:cache] << {"ID" => "missing-age", "Reclaimable" => true}
    _out, err, status = run_cleanup("--dry-run")
    assert status.success?, err
    before = err.lines.map { |l| JSON.parse(l) }.find { |r| r["event"] == "cache-before" }
    assert_empty before["eligible"]
    assert_equal ["old-cache"], before["age_eligible"]
    assert_equal %w[old-cache missing-age], before["protected"]
    refute commands.any? { |c| c[1] == "prune" || c[1] == "rm" }
  end

  def test_initial_protection_and_unknown_releases_are_never_removed
    [INITIAL.first, "9" * 40].each do |sha|
      @fixture[:containers] = [container(sha)]
      _out, err, status = run_cleanup("--apply")
      assert status.success?, err
      refute commands.any? { |c| c.first(2) == ["container", "rm"] }
    end
  end

  def test_lock_content_and_inode_survive_and_busy_lock_excludes_docker
    lock = File.join(@state, "deploy.lock")
    File.write(lock, "never truncate")
    inode = File.stat(lock).ino
    File.open(lock, "r+") do |f|
      f.flock(File::LOCK_EX | File::LOCK_NB)
      _out, err, status = run_cleanup("--apply")
      assert_equal 75, status.exitstatus, err
      refute File.exist?(@env.fetch("COMMAND_LOG"))
    end
    _out, err, status = run_cleanup("--dry-run")
    assert status.success?, err
    assert_equal inode, File.stat(lock).ino
    assert_equal "never truncate", File.read(lock)
  end

  def test_low_disk_preflight_attempts_only_cache_then_aborts_before_locked
    run_cleanup("--dry-run", "--cache-only")
    File.write(@env.fetch("COMMAND_LOG"), "")
    harness = <<~PYTHON
      import runpy, sys
      module = runpy.run_path(sys.argv.pop(1))
      module['Cleanup'].__init__.__globals__['STATE'] = module['Path'].home() / '.local/share/prosecho'
      module['Cleanup'].capacity = lambda self: 0
      module['Path'].read_text = lambda self: 'MemAvailable: 8388608 kB\\n'
      module['main']()
    PYTHON
    out, err, status = Open3.capture3(@env, "python3", "-c", harness, SCRIPT, "--apply", "--hold-lock")
    refute status.success?, err
    refute_includes out, "LOCKED"
    assert commands.any? { |c| c.first(2) == ["buildx", "prune"] }
    refute commands.any? { |c| c[0] == "container" || c[0] == "image" }
  end

  def test_malformed_ledger_skips_release_cleanup_but_permits_cache
    @records = {not: "a success ledger"}
    _out, err, status = run_cleanup("--apply")
    assert status.success?, err
    assert_includes err, "release-cleanup-skipped"
    assert commands.any? { |c| c.first(2) == ["buildx", "prune"] }
    refute commands.any? { |c| c[1] == "rm" }
  end

  def test_missing_protection_file_fails_closed
    File.unlink(File.join(@state, "protect.json"))
    _out, err, status = run_cleanup("--apply")
    assert status.success?, err
    assert_includes err, "release-cleanup-skipped"
    refute commands.any? { |c| c[1] == "rm" }
  end

  def test_null_or_naive_cache_timestamp_is_protected
    @fixture[:cache] = [
      {"ID" => "null", "Reclaimable" => true, "LastUsedAt" => nil},
      {"ID" => "naive", "Reclaimable" => true, "LastUsedAt" => "2020-01-01T00:00:00"}
    ]
    _out, err, status = run_cleanup("--dry-run")
    assert status.success?, err
    before = err.lines.map { |l| JSON.parse(l) }.find { |r| r["event"] == "cache-before" }
    assert_empty before["eligible"]
    assert_equal %w[null naive], before["protected"]
  end

  def test_old_known_success_removes_only_exact_container_and_repository_tag
    _out, err, status = run_cleanup("--apply")
    assert status.success?, err
    assert_includes commands, ["container", "rm", "1" * 64]
    assert_includes commands, ["image", "rm", "--no-prune", "#{REPO}:#{@old}"]
    final = JSON.parse(File.read(@env.fetch("DOCKER_FIXTURE")))
    assert_equal ["retained-parent"], final["parents"]
    refute final["implicit_parent_removed"]
    assert_includes commands, ["buildx", "prune", "--builder", "default", "--filter", "until=168h", "--max-used-space", "5368709120", "--force"]
    refute commands.flatten.any? { |a| %w[system volume -v].include?(a) }
    refute commands.any? { |c| c[1] == "prune" && c.include?("--all") }
  end

  def test_unknown_reclaimable_age_blocks_entire_apply_even_above_cache_budget
    [nil, "not-a-timestamp", "2020-01-01T00:00:00"].each do |age|
      @fixture[:cache] = [
        {"ID" => "old-cache", "Reclaimable" => true, "LastUsedAt" => "2020-01-01T00:00:00Z", "Size" => "6000000000"},
        {"ID" => "unknown-age", "Reclaimable" => true, "LastUsedAt" => age, "Size" => "6000000000"}
      ]
      _out, err, status = run_cleanup("--apply", "--cache-only")
      assert status.success?, err
      assert_includes err, "cache-prune-skipped"
      refute commands.any? { |c| c[1] == "prune" }
      assert_equal 2, JSON.parse(File.read(@env.fetch("DOCKER_FIXTURE")))["cache"].size
    end
  end

  def test_low_disk_with_unknown_cache_age_still_aborts_without_prune
    @fixture[:cache] << {"ID" => "unknown", "Reclaimable" => true}
    run_cleanup("--dry-run", "--cache-only")
    harness = <<~PYTHON
      import runpy, sys
      module = runpy.run_path(sys.argv.pop(1))
      module['Cleanup'].__init__.__globals__['STATE'] = module['Path'].home() / '.local/share/prosecho'
      module['Cleanup'].capacity = lambda self: 0
      module['Path'].read_text = lambda self: 'MemAvailable: 8388608 kB\\n'
      module['main']()
    PYTHON
    out, err, status = Open3.capture3(@env, "python3", "-c", harness, SCRIPT, "--apply", "--hold-lock")
    refute status.success?, err
    refute_includes out, "LOCKED"
    assert_includes err, "cache-prune-skipped"
    refute commands.any? { |c| c[1] == "prune" }
  end

  def test_stopped_container_actual_image_digest_must_match_success
    @fixture[:images].values.first["RepoDigests"] = ["#{REPO}@sha256:" + "0" * 64]
    _out, err, status = run_cleanup("--apply")
    assert status.success?, err
    refute commands.any? { |c| c[1] == "rm" }
  end

  def test_running_image_references_are_refreshed_before_container_removal
    other = container("9" * 40, id: "2" * 64)
    other["Name"] = "/unrelated-worker"
    @fixture[:containers] << other
    @fixture[:start_other_on_recheck] = true
    _out, err, status = run_cleanup("--apply")
    assert status.success?, err
    refute commands.any? { |c| c[1] == "rm" }
  end

  def test_both_explicit_replaced_container_name_forms_are_recognized
    %w[_replaced_ -replaced-].each do |separator|
      before = File.exist?(@env.fetch("COMMAND_LOG")) ? commands.count { |c| c[0, 2] == ["container", "rm"] } : 0
      @fixture[:containers] = [container(@old)]
      @fixture[:containers][0]["Name"] += separator + "20260901"
      _out, err, status = run_cleanup("--apply")
      assert status.success?, err
      assert_includes commands, ["container", "rm", "1" * 64]
      assert_equal before + 1, commands.count { |c| c[0, 2] == ["container", "rm"] }
    end
  end

  def test_strict_ledger_schema_rejects_non_objects_bad_fields_and_nonfinite_times
    invalid = [nil, [], "record", {sha: 1, digest: @digest, at: 1},
      {sha: @old, digest: nil, at: 1}, {sha: @old, digest: @digest, at: true},
      {sha: @old, digest: @digest, at: Float::NAN},
      {sha: @old, digest: @digest, at: Float::INFINITY},
      {sha: @old, digest: @digest, at: Time.now.to_i + 3600}]
    invalid.each do |record|
      @records[0] = record
      _out, err, status = run_cleanup("--apply")
      assert status.success?, err
      assert_includes err, "release-cleanup-skipped"
      refute commands.any? { |c| c[1] == "rm" }
    end
  end

  def test_state_and_all_user_parents_reject_symlinks_or_write_permissions
    [@directory, File.join(@directory, ".local"), File.join(@directory, ".local/share"), @state].each do |path|
      original = File.stat(path).mode & 0o777
      File.chmod(0o777, path)
      _out, err, status = run_cleanup("--apply")
      refute status.success?, err
      refute File.exist?(@env.fetch("COMMAND_LOG"))
      File.chmod(original, path)
    end
    [File.join(@directory, ".local"), File.join(@directory, ".local/share"), @state].each do |path|
      File.rename(path, path + ".original")
      File.symlink(path + ".original", path)
      _out, err, status = run_cleanup("--apply")
      refute status.success?, err
      refute File.exist?(@env.fetch("COMMAND_LOG"))
      File.unlink(path)
      File.rename(path + ".original", path)
    end
    File.chmod(0o755, @state)
    _out, err, status = run_cleanup("--apply")
    refute status.success?, err
    refute File.exist?(@env.fetch("COMMAND_LOG"))
  end

  def test_replaced_state_directory_is_rejected_on_each_docker_call
    harness = <<~PYTHON
      import runpy, sys, os
      module = runpy.run_path(sys.argv[1])
      module['Cleanup'].__init__.__globals__['STATE'] = module['Path'].home() / '.local/share/prosecho'
      cleanup = module['Cleanup']()
      state = cleanup.path.parent
      os.rename(state, str(state) + '.original')
      state.mkdir(mode=0o700)
      cleanup.docker('info', '--format', '{{.DockerRootDir}}')
    PYTHON
    _out, err, status = Open3.capture3(@env, "python3", "-c", harness, SCRIPT)
    refute status.success?, err
    assert_includes err, "Replaced deployment state path"
    refute File.exist?(@env.fetch("COMMAND_LOG"))
  end

  def test_timeout_kills_fd_dropping_term_resistant_plugin_and_blocks_next_operation
    @fixture[:fork_plugin] = true
    @env["TEST_DOCKER_TIMEOUT"] = "0.5"
    @env["PLUGIN_PID"] = File.join(@directory, "plugin.pid")
    lock = File.join(@state, "deploy.lock")
    thread = Thread.new { run_cleanup("--apply", "--cache-only") }
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
    until File.exist?(@env["PLUGIN_PID"])
      raise "fake plugin did not start" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.01
    end
    File.open(lock, "r+") { |f| refute f.flock(File::LOCK_EX | File::LOCK_NB) }
    _out, err, status = thread.value
    refute status.success?, err
    pid = Integer(File.read(@env["PLUGIN_PID"]))
    assert_raises(Errno::ESRCH) { Process.kill(0, pid) }
    assert File.exist?(File.join(@state, "cleanup-uncertain"))
    count = commands.size
    @env.delete("TEST_DOCKER_TIMEOUT")
    _out, err, status = run_cleanup("--apply", "--hold-lock")
    refute status.success?, err
    assert_includes err, "operator daemon verification required"
    assert_equal count, commands.size
    assert File.exist?(File.join(@state, "cleanup-uncertain"))
  ensure
    thread&.join
  end

  def test_restarted_container_is_revalidated_and_preserved
    @fixture[:restart] = true
    _out, err, status = run_cleanup("--apply")
    assert status.success?, err
    refute commands.any? { |c| c[1] == "rm" }
  end

  def test_running_container_using_same_image_protects_stopped_release
    other = container("9" * 40, id: "2" * 64, running: true)
    @fixture[:containers] << other
    _out, err, status = run_cleanup("--apply")
    assert status.success?, err
    refute commands.any? { |c| c[1] == "rm" }
  end

  def test_symlink_lock_is_rejected_before_docker
    File.symlink(File.join(@directory, "target"), File.join(@state, "deploy.lock"))
    _out, err, status = run_cleanup("--apply")
    refute status.success?, err
    refute File.exist?(@env.fetch("COMMAND_LOG"))
  end

  def test_success_requires_exact_running_digest_and_routed_200
    @fixture[:containers][0]["State"] = {"Running" => true, "Status" => "running"}
    @records = []
    run_cleanup("--dry-run")
    harness = <<~PYTHON
      import runpy, sys, json
      module = runpy.run_path(sys.argv[1])
      module['Cleanup'].__init__.__globals__['STATE'] = module['Path'].home() / '.local/share/prosecho'
      class Response:
          status = int(sys.argv[4])
          def __enter__(self): return self
          def __exit__(self, *args): pass
      class Opener:
          def open(self, request, timeout):
              assert request.full_url == 'http://127.0.0.1:8080/ready'
              assert request.get_header('Host') == 'prosecho.menloparking.com'
              return Response()
      module['urllib'].request.build_opener = lambda *args: Opener()
      cleanup = module['Cleanup'](True)
      cleanup.success(sys.argv[2], sys.argv[3])
    PYTHON
    _out, err, status = Open3.capture3(@env, "python3", "-c", harness, SCRIPT, @old, @digest, "503")
    refute status.success?, err
    assert_equal [], JSON.parse(File.read(File.join(@state, "success.json")))
    _out, err, status = Open3.capture3(@env, "python3", "-c", harness, SCRIPT, @old, "sha256:" + "0" * 64, "200")
    refute status.success?, err
    _out, err, status = Open3.capture3(@env, "python3", "-c", harness, SCRIPT, @old, @digest, "200")
    assert status.success?, err
    record = JSON.parse(File.read(File.join(@state, "success.json"))).fetch(0)
    assert_equal @old, record.fetch("sha")
    assert_equal @digest, record.fetch("digest")
    assert_operator record.fetch("at"), :>, Time.now.to_i - 30
  end

  def test_replaced_lock_inode_is_rejected
    harness = <<~PYTHON
      import runpy, sys, os
      module = runpy.run_path(sys.argv[1])
      module['Cleanup'].__init__.__globals__['STATE'] = module['Path'].home() / '.local/share/prosecho'
      cleanup = module['Cleanup']()
      os.rename(cleanup.path, str(cleanup.path) + '.original')
      cleanup.path.touch()
      cleanup.validate_lock()
    PYTHON
    _out, err, status = Open3.capture3(@env, "python3", "-c", harness, SCRIPT)
    refute status.success?, err
    assert_includes err, "Unsafe or replaced deploy.lock"
    refute File.exist?(@env.fetch("COMMAND_LOG"))
  end

  def test_wrong_digest_or_any_container_reference_protects_image
    @fixture[:containers] = []
    @fixture[:images].values.first["RepoDigests"] = ["#{REPO}@sha256:" + "0" * 64]
    _out, err, status = run_cleanup("--apply")
    assert status.success?, err
    refute commands.any? { |c| c.first(2) == ["image", "rm"] }
  end

  def test_unrelated_stopped_container_reference_protects_image
    other = container("9" * 40)
    other["Name"] = "/unrelated-job"
    @fixture[:containers] = [other]
    _out, err, status = run_cleanup("--apply")
    assert status.success?, err
    refute commands.any? { |c| c[1] == "rm" }
  end

  def test_removal_count_is_bounded
    @fixture[:containers] = 25.times.map { |i| container(@old, id: i.to_s(16).rjust(64, "0")) }
    _out, err, status = run_cleanup("--apply")
    assert status.success?, err
    assert_equal 20, commands.count { |c| c[1] == "rm" }
  end

  def test_wrong_labels_recent_exit_and_retained_successes_are_protected
    @fixture[:containers][0]["Config"]["Labels"]["service"] = "other"
    @fixture[:containers] << container("e" * 40, id: "2" * 64)
    recent = container(@old, id: "3" * 64)
    recent["State"]["FinishedAt"] = Time.now.utc.iso8601
    @fixture[:containers] << recent
    _out, err, status = run_cleanup("--apply")
    assert status.success?, err
    refute commands.any? { |c| c[1] == "rm" }
  end
end
