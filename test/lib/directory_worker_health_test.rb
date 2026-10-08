require "test_helper"

class DirectoryWorkerHealthTest < ActiveSupport::TestCase
  test "stale workers and unrelated queues do not report directory work as online" do
    process = SolidQueue::Process.create!(kind: "Worker", pid: 12345,
      name: "directory-health-fixture", hostname: "fixture-host",
      last_heartbeat_at: 10.minutes.ago, metadata: {"queues" => "directory"})
    assert_not Directory::WorkerHealth.online?
    process.update!(last_heartbeat_at: Time.current, metadata: {"queues" => "foundation,default"})
    assert_not Directory::WorkerHealth.online?
    process.update!(metadata: {"queues" => "directory,foundation,default"})
    assert Directory::WorkerHealth.online?
  end

  test "development Puma starts Solid Queue but production leaves it separate" do
    plugins = []
    context = Object.new
    context.define_singleton_method(:threads) { |*args| }
    context.define_singleton_method(:port) { |*args| }
    context.define_singleton_method(:pidfile) { |*args| }
    context.define_singleton_method(:plugin) { |name| plugins << name }
    original = ENV["RAILS_ENV"]
    ENV["RAILS_ENV"] = "development"
    context.instance_eval(Rails.root.join("config/puma.rb").read)
    assert_includes plugins, :solid_queue
    plugins.clear
    ENV["RAILS_ENV"] = "production"
    context.instance_eval(Rails.root.join("config/puma.rb").read)
    assert_not plugins.include?(:solid_queue)
  ensure
    ENV["RAILS_ENV"] = original
  end
end
