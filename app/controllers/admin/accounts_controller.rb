module Admin
  class AccountsController < BaseController
    def create
      values = account_attributes
      provisioner.provision(email: values.delete(:email), password: values.delete(:password),
        password_confirmation: values.delete(:password_confirmation) || "",
        attributes: values, campus_ids: campus_ids)
      redirect_to admin_root_path, notice: "Account created."
    rescue ActiveRecord::RecordInvalid => error
      render_account(error.record, new_record: true, status: :unprocessable_content)
    end

    def edit
      render_account(User.find(params[:id]))
    end

    def new
      render_account(User.new, new_record: true)
    end

    def update
      user = User.find(params[:id])
      values = account_attributes
      if values[:password].blank?
        values.except!(:password, :password_confirmation)
      else
        values[:password_confirmation] ||= ""
      end
      provisioner.update(user: user, attributes: values, campus_ids: campus_ids)
      redirect_to admin_root_path, notice: "Account updated."
    rescue ActiveRecord::RecordInvalid => error
      render_account(error.record, status: :unprocessable_content)
    end

    private

    def account_attributes
      params.require(:user).permit(:active, :email, :password, :password_confirmation,
        :role, :view_history, :view_locations, :view_photos).to_h.symbolize_keys
    end

    def campus_ids
      params.require(:user).permit(campus_ids: []).fetch(:campus_ids, nil)
    end

    def render_account(user, new_record: false, status: :ok)
      render Components::Admin::AccountForm.new(user: user, campuses: Campus.order(:name),
        new_record: new_record), status: status
    end
  end
end
