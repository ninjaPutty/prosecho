require "open3"
require "shellwords"

module ProductionCommand
  ROOT = File.expand_path("..", __dir__)
  HOST = "ssh-prosecho.menloparking.com"

  def self.main(args)
    mode = args.shift
    interactive = mode != "runner"
    command = case mode
    when "console"
      ["bin/rails", "console", "-e", "production", *args]
    when "runner"
      abort "Usage: bin/prod/runner RUBY_CODE|LOCAL_FILE|- [ARG ...]" if args.empty?
      source = args.shift
      if File.file?(source)
        # Rails runner '-' reads local content directly; no remote temporary file is needed.
        $stdin.reopen(source, "r")
        source = "-"
      end
      ["bin/rails", "runner", "-e", "production", source, *args]
    when "shell"
      abort "Usage: bin/prod/shell" unless args.empty?
      ["sh"]
    when "ssh"
      abort "Usage: bin/prod/ssh" unless args.empty?
      nil
    else
      abort "Unknown production command"
    end

    # Resolve the real client before adding helpers; bin/prod/ssh is a user entry point.
    client = ENV.fetch("PATH").split(File::PATH_SEPARATOR).map { |path| File.join(path, "ssh") }
      .find { |path| File.executable?(path) && File.expand_path(path) != "#{ROOT}/bin/prod/ssh" }
    abort "SSH client is missing" unless client
    ENV["PATH"] = "#{ROOT}/bin/prod:#{ENV.fetch("PATH")}"
    deployment = ENV["DOCKER_HOST"] == "ssh://deploy@prosecho-deploy-cloudflare"
    host = deployment ? "prosecho-deploy-cloudflare" : HOST
    config = deployment ? "ssh.deploy" : "ssh.prod"
    ssh = [client, "-F", "#{ROOT}/.devcontainer/#{config}", "-o", "ConnectTimeout=10"]
    exec(*ssh, "-tt", host) if mode == "ssh"
    query = ["docker", "container", "ls", "--no-trunc", "--filter", "label=service=prosecho",
      "--filter", "label=role=web", "--format", "{{.ID}} {{.Names}}"].shelljoin
    output, status = Open3.capture2(*ssh, "-T", host, query, stdin_data: "")
    abort "Could not discover the production app container" unless status.success?
    rows = output.lines.map(&:split).select do |row|
      row.length == 2 && row[0].match?(/\A[0-9a-f]{64}\z/) &&
        row[1].match?(/\Aprosecho-web-[0-9a-f]{40}\z/)
    end
    abort "Expected exactly one running production app container; found #{rows.size}" unless rows.one?
    remote = ["docker", "exec", interactive ? "-it" : "-i", rows.first.first, *command]
    exec(*ssh, interactive ? "-tt" : "-T", host, remote.shelljoin)
  end
end

ProductionCommand.main(ARGV) if $PROGRAM_NAME == __FILE__
