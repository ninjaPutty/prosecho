class User < ApplicationRecord
  devise :database_authenticatable, :lockable, :timeoutable, :validatable

  has_many :campus_accesses, dependent: :destroy
  has_many :campuses, through: :campus_accesses

  validates :active, :view_history, :view_locations, :view_photos, inclusion: {in: [true, false]}
  validates :role, inclusion: {in: %w[administrator staff]}

  def active_for_authentication?
    super && active?
  end

  def administrator?
    active? && role == "administrator"
  end

  # Devise's bcrypt-prefix salt would not invalidate sessions for Argon2id hashes.
  def authenticatable_salt
    Digest::SHA256.hexdigest(encrypted_password)
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
end
