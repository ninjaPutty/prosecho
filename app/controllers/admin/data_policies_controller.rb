module Admin
  class DataPoliciesController < BaseController
    def show
      render_policy(DataPolicy.current.apply_form_defaults)
    end

    def update
      policy = provisioner.save_data_policy(attributes: policy_attributes,
        revision: params.require(:data_policy)[:revision])
      message = if policy.confirmed?
        "Agreed data decisions recorded."
      else
        "Data decisions saved as a draft."
      end
      redirect_to admin_data_policy_path, notice: message
    rescue ActiveRecord::RecordInvalid => error
      render_policy(error.record, status: :unprocessable_content)
    rescue DataPolicy::Conflict, ActiveRecord::StaleObjectError
      flash.now[:alert] = "Another administrator changed these decisions. Review the latest values."
      render_policy(DataPolicy.current, status: :conflict)
    end

    private

    def policy_attributes
      values = params.require(:data_policy).permit(:address_handling, :address_source,
        :attribute_keys_text, :backup_retention_days, :family_status_meaning,
        :history_retention_days, :household_handling, :household_source,
        :log_retention_days, :profile_retention_days, :retention_notes, :status,
        selected_fields: []).to_h.symbolize_keys
      if values.key?(:selected_fields)
        values[:selected_fields] = Array(values[:selected_fields]).reject(&:blank?).uniq
      end
      values
    end

    def render_policy(policy, status: :ok)
      render Components::Admin::DataPolicyForm.new(policy: policy), status: status
    end
  end
end
