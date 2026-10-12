class AuthenticatorsController < StaffController
  before_action :require_pending_authenticator, only: %i[new create]
  skip_before_action :authenticate_user!, :active_account, only: %i[new create]

  rate_limit to: 5, within: 5.minutes, only: :create

  def new
    authenticator_user.start_authenticator_enrollment! unless authenticator_user.authenticator_enabled?
    render Components::Authenticator.new(user: authenticator_user, message: flash[:alert])
  end

  def create
    if current_user && !authenticator_user.authenticator_enabled?
      unless current_user.valid_password?(params[:current_password])
        return render_form("Enter your current password to enable an authenticator.")
      end
    end

    if params[:recovery_code].present?
      return recover_authenticator if authenticator_user.recover_authenticator!(params[:recovery_code])
    elsif authenticator_user.authenticator_enabled?
      complete_second_factor if authenticator_user.verify_authenticator_code(params[:otp_code])
    elsif authenticator_user.enable_authenticator!(params[:otp_code])
      complete_second_factor
    end

    return if performed?

    render_form("Enter a current six-digit code from your authenticator app.")
  end

  def recovery_codes
    codes = session.delete(:authenticator_recovery_codes)
    return redirect_to new_authenticator_path unless codes.present?

    render Components::AuthenticatorRecoveryCodes.new(codes: codes)
  end

  private

  def complete_second_factor
    user = authenticator_user
    codes = user.new_recovery_codes
    reset_session
    sign_in(user)
    if codes.present?
      session[:authenticator_recovery_codes] = codes
      redirect_to recovery_codes_authenticator_path
    else
      redirect_to dashboard_path, notice: "Authenticator verified."
    end
  end

  def current_pending_user
    @current_pending_user ||= User.find_by(id: session[:pending_authenticator_user_id])
  end

  def authenticator_user
    current_pending_user || current_user
  end

  def require_pending_authenticator
    if session[:pending_authenticator_user_id].present?
      valid = current_pending_user &&
        session[:pending_authenticator_salt] == current_pending_user.authenticatable_salt &&
        session[:pending_authenticator_started_at].to_i > 5.minutes.ago.to_i
      unless valid
        reset_session
        return redirect_to new_user_session_path, alert: "Sign in again to continue."
      end
    end
    return if authenticator_user&.active? && !authenticator_user.access_locked?

    redirect_to new_user_session_path, alert: "Sign in again to continue."
  end

  def recover_authenticator
    user = authenticator_user
    sign_out(:user)
    reset_session
    session[:pending_authenticator_user_id] = user.id
    session[:pending_authenticator_salt] = user.authenticatable_salt
    session[:pending_authenticator_started_at] = Time.current.to_i
    AccessEvent.create!(actor: user, resource: "account", resource_id: user.id, outcome: "updated")
    redirect_to new_authenticator_path, notice: "Recovery verified. Enroll your new phone to continue."
  end

  def render_form(message)
    render Components::Authenticator.new(user: authenticator_user, message: message),
      status: :unprocessable_content
  end
end
