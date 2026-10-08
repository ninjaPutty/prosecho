class PersonRefreshRun < ApplicationRecord
  class NotReady < StandardError; end
  class AlreadyRunning < StandardError; end
  ERROR_MESSAGES = {
    "access_or_policy_changed" => "Campus access or data decisions changed. Start a new refresh.",
    "invalid_page_contract" => "Rock returned an unexpected page or policy revision.",
    "invalid_page_cursor" => "Rock returned a page that did not advance the source ID cursor.",
    "invalid_page_size" => "The server's Rock person page size must be a whole number from 1 to 500.",
    "invalid_person_identity" => "A Rock person has an invalid identity or campus.",
    "invalid_source_records" => "The earlier run failed a source-data check; " \
      "no detailed reason was recorded.",
    "page_limit_exceeded" => "The refresh reached its configured page limit.",
    "publication_identity_conflict" => "A directory identity conflicted while publishing.",
    "publication_validation_failed" => "A staged record failed directory validation while publishing.",
    "rock_not_configured" => "The server's Rock connection is not configured.",
    "rock_read_failed" => "A Rock read failed. Saved pages are intact; retrying automatically.",
    "source_population_mismatch" => "Rock returned records outside the requested campus or population.",
    "staging_identity_conflict" => "An identity conflicted while saving a page.",
    "staging_validation_failed" => "A record failed validation while saving a page."
  }.freeze
  belongs_to :actor, class_name: "User"
  has_many :entries, class_name: "PersonRefreshEntry", foreign_key: :run_id, dependent: :delete_all
  validates :status, inclusion: {in: %w[queued running succeeded failed]}

  scope :active, -> { where(status: %w[queued running]) }

  def active?
    status.in?(%w[queued running])
  end

  def checkpoint_authorized?
    policy = DataPolicy.current
    actor.reload.active? && !actor.access_locked? &&
      (campus_ids - actor.campuses.active.pluck(:id)).empty? &&
      policy.confirmed? && policy.valid? && policy.revision == policy_revision
  end

  def diagnostic_details
    checkpoint_authorized? ? error_details : error_details.except("rock_id", "last_rock_id")
  end

  def dispatch!
    with_lock do
      return false unless active?
      return false if live_job?

      job = PersonRefreshJob.set(wait_until: retry_at || Time.current).perform_later(id)
      raise NotReady, "The refresh queue is unavailable; saved progress is intact" unless job
      update!(job_id: job.job_id)
      true
    end
  end

  def error_message
    ERROR_MESSAGES.fetch(error_code, "The refresh could not finish.")
  end

  def live_job?
    job = SolidQueue::Job.find_by(active_job_id: job_id) if job_id
    return false unless job && !job.finished? && !job.failed_execution
    return true if job.ready_execution || job.scheduled_execution || job.blocked_execution

    process = job.claimed_execution&.process
    process&.last_heartbeat_at &&
      process.last_heartbeat_at >= SolidQueue.process_alive_threshold.seconds.ago
  end

  def resumable?
    status == "failed" && checkpoint_retained? && error_code != "access_or_policy_changed" &&
      checkpoint_authorized?
  end

  def resume!
    with_lock do
      unless status == "failed" && checkpoint_retained? && error_code != "access_or_policy_changed"
        raise NotReady, "This run has no retained checkpoint. Start a new refresh."
      end
      unless checkpoint_authorized?
        raise NotReady, "Saved work no longer matches campus access or data decisions. " \
          "Start a new refresh."
      end
      update!(status: "queued", error_code: nil, finished_at: nil, retry_at: nil)
    end
    self
  rescue ActiveRecord::RecordNotUnique
    raise AlreadyRunning, "A directory refresh is already queued or running"
  end

  def self.start!(actor:, campus_ids: nil)
    unless actor&.active? && !actor.access_locked? && actor.campuses.active.exists?
      raise NotReady, "Active campus access is required"
    end
    policy = DataPolicy.current
    raise NotReady, "Agreed data decisions are required" unless policy.confirmed? && policy.valid?
    allowed_ids = actor.campuses.active.order(:id).pluck(:id)
    requested = campus_ids || allowed_ids
    unless requested.is_a?(Array) && requested.any? && (requested - allowed_ids).empty?
      raise NotReady, "Choose an assigned campus for refresh"
    end
    create!(actor: actor, campus_ids: requested, checkpoint_retained: true, last_rock_id: 0,
      policy_revision: policy.revision)
  rescue ActiveRecord::RecordNotUnique
    raise AlreadyRunning, "A directory refresh is already queued or running"
  end
end
