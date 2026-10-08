module Directory
  module WorkerHealth
    def self.online?
      cutoff = SolidQueue.process_alive_threshold.seconds.ago
      SolidQueue::Process.where(kind: "Worker", last_heartbeat_at: cutoff..).any? do |process|
        queues = process.metadata.fetch("queues", "").to_s.split(",")
        queues.include?("directory") || queues.include?("*")
      end
    end
  end
end
