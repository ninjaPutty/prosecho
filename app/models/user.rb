class User < ApplicationRecord
  devise :database_authenticatable, :lockable, :timeoutable, :validatable

  has_many :campus_accesses, dependent: :destroy
  has_many :campuses, through: :campus_accesses

  validates :active, :view_history, :view_locations, :view_photos, inclusion: {in: [true, false]}
  validates :role, inclusion: {in: %w[administrator staff]}

  attr_reader :new_recovery_codes

  def active_for_authentication?
    super && active?
  end

  def authenticator_enabled?
    otp_enabled_at.present? && otp_secret_ciphertext.present?
  end

  def administrator?
    active? && role == "administrator"
  end

  # Devise's bcrypt-prefix salt would not invalidate sessions for Argon2id hashes.
  def authenticatable_salt
    Digest::SHA256.hexdigest([encrypted_password, otp_enabled_at, otp_session_version].join(":"))
  end

  def can_access?(campus_id, capability)
    return false unless active? && !access_locked? && campus_id.present?
    return false unless campuses.active.exists?(id: campus_id)

    case capability
    when :directory then true
    when :history then view_history?
    when :locations then view_locations?
    when :photos then view_photos?
    else false
    end
  end

  def password=(password)
    @password = password
    if password.present?
      self.encrypted_password = Argon2::Password.new(profile: :rfc_9106_low_memory).create(password)
    end
  end

  def valid_password?(password)
    return false unless encrypted_password.start_with?("$argon2id$") && password.present?

    Argon2::Password.verify_password(password, encrypted_password)
  rescue Argon2::ArgonHashFail
    false
  end

  def start_authenticator_enrollment!
    return if authenticator_enabled? || otp_secret_ciphertext.present?

    self.otp_last_used_at = nil
    self.otp_secret_ciphertext = self.class.otp_encryptor.encrypt_and_sign(ROTP::Base32.random_base32)
    save!
  end

  def authenticator_provisioning_uri
    authenticator_totp.provisioning_uri(email)
  end

  def authenticator_setup_key
    self.class.otp_encryptor.decrypt_and_verify(otp_secret_ciphertext)
  end

  def enable_authenticator!(code)
    with_lock do
      return false if authenticator_enabled? || !active_for_authentication?
      unless authenticate_totp(code)
        record_authenticator_failure!
        return false
      end

      self.otp_enabled_at = Time.current
      self.otp_required = true
      self.otp_failed_attempts = 0
      @new_recovery_codes = Array.new(10) { SecureRandom.hex(16) }
      self.otp_recovery_code_digests = @new_recovery_codes.map { |value| Digest::SHA256.hexdigest(value) }
      save!
    end
  end

  def reset_authenticator!
    with_lock do
      update!(otp_enabled_at: nil, otp_failed_attempts: 0, otp_last_used_at: nil,
        otp_recovery_code_digests: [], otp_required: true, otp_secret_ciphertext: nil,
        otp_session_version: SecureRandom.hex(16))
    end
  end

  def recover_authenticator!(code)
    with_lock do
      return false unless authenticator_enabled? && active_for_authentication?

      digest = Digest::SHA256.hexdigest(code.to_s.strip.downcase)
      valid = otp_recovery_code_digests.any? do |stored|
        ActiveSupport::SecurityUtils.secure_compare(stored, digest)
      end
      return false unless valid

      reset_authenticator!
      true
    end
  end

  def verify_authenticator_code(code)
    with_lock do
      return false unless authenticator_enabled? && active_for_authentication?

      if authenticate_totp(code)
        self.otp_failed_attempts = 0
        save!
      else
        record_authenticator_failure!
        false
      end
    end
  end

  def self.otp_encryptor
    @otp_encryptor ||= ActiveSupport::MessageEncryptor.new(
      Rails.application.key_generator.generate_key("user authenticator secrets", 32),
      cipher: "aes-256-gcm"
    )
  end

  private

  def record_authenticator_failure!
    self.otp_failed_attempts += 1
    self.locked_at = Time.current if otp_failed_attempts >= self.class.maximum_attempts
    save!
  end

  def authenticate_totp(code)
    return false unless otp_secret_ciphertext.present? && code.to_s.match?(/\A\d{6}\z/)

    verified_at = authenticator_totp.verify(code, drift_behind: 30, drift_ahead: 30)
    return false if verified_at.nil?
    return false if otp_last_used_at.present? && verified_at <= otp_last_used_at.to_i

    self.otp_last_used_at = Time.at(verified_at)
    true
  rescue ActiveSupport::MessageEncryptor::InvalidMessage
    false
  end

  def authenticator_totp
    secret = self.class.otp_encryptor.decrypt_and_verify(otp_secret_ciphertext)
    ROTP::TOTP.new(secret, issuer: "Prosecho")
  end
end
