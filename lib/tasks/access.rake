namespace :access do
  def access_actor
    Access::Provisioner.new(actor: User.find(ENV.fetch("ACTOR_ID")))
  end

  def access_password
    # Passwords enter via stdin, never command arguments, environment variables, or output.
    value = $stdin.gets&.chomp
    abort "A password is required on standard input" if value.blank?
    value
  end

  desc "Create the first administrator (password on stdin, EMAIL required)"
  task bootstrap: :environment do
    user = Access::Provisioner.bootstrap(email: ENV.fetch("EMAIL"), password: access_password)
    puts "Administrator created: #{user.id}. No pastoral campus access granted."
  end

  desc "Grant one existing campus (ACTOR_ID, USER_ID, CAMPUS_ID)"
  task grant: :environment do
    access_actor.grant(user: User.find(ENV.fetch("USER_ID")),
      campus: Campus.find(ENV.fetch("CAMPUS_ID")))
    puts "Campus access granted."
  end

  desc "Provision staff (ACTOR_ID, EMAIL required; password on stdin)"
  task provision: :environment do
    actor = access_actor
    user = actor.provision(email: ENV.fetch("EMAIL"), password: access_password)
    puts "Staff account created: #{user.id}. No campus access granted."
  end

  desc "Revoke one campus (ACTOR_ID, USER_ID, CAMPUS_ID)"
  task revoke: :environment do
    access_actor.revoke(user: User.find(ENV.fetch("USER_ID")),
      campus: Campus.find(ENV.fetch("CAMPUS_ID")))
    puts "Campus access revoked."
  end

  desc "Update account (ACTOR_ID, USER_ID, SETTING and VALUE; password uses stdin)"
  task update: :environment do
    setting = ENV.fetch("SETTING").to_sym
    value = if setting == :password
      access_password
    elsif setting == :role
      ENV.fetch("VALUE")
    else
      input = ENV.fetch("VALUE")
      abort "VALUE must be true or false" unless %w[true false].include?(input)
      input == "true"
    end
    access_actor.update(user: User.find(ENV.fetch("USER_ID")), attributes: {setting => value})
    puts "Account updated."
  end
end

namespace :pastoral do
  desc "Report local readiness without contacting Rock or map providers"
  task readiness: :environment do
    settings = Pastoral::Configuration.load
    puts "Read-only: #{settings.read_only?}; live sync enabled: #{settings.live_sync_enabled?}"
    settings.blockers.each { |blocker| puts "- #{blocker}" }
  end
end
