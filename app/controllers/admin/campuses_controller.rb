module Admin
  class CampusesController < BaseController
    def edit
      render_campus(Campus.find(params[:id]))
    end

    def import
      result = Integrations::Rock::CampusImporter.new(actor: current_user).call
      total = result.created + result.updated + result.unchanged
      message = "Fetched #{total} campuses from Rock: #{result.created} added, " \
        "#{result.updated} updated, #{result.unchanged} unchanged."
      redirect_to admin_root_path, notice: message
    rescue Integrations::Rock::ReadClient::ConfigurationError
      redirect_to admin_root_path,
        alert: "Rock connection is not configured. No campuses were changed."
    rescue Integrations::Rock::ReadClient::ReadError,
      Integrations::Rock::CampusImporter::ImportError
      redirect_to admin_root_path,
        alert: "Could not fetch campuses from Rock. No campuses were changed. Please try again."
    end

    def update
      provisioner.save_campus(campus: Campus.find(params[:id]), attributes: campus_attributes)
      redirect_to admin_root_path, notice: "Campus updated."
    rescue ActiveRecord::RecordInvalid => error
      render_campus(error.record, status: :unprocessable_content)
    end

    private

    def campus_attributes
      params.require(:campus).permit(:active, :name, :parent_id).to_h.symbolize_keys
    end

    def render_campus(campus, status: :ok)
      component = Components::Admin::CampusForm.new(campus: campus,
        parents: Campus.where.not(id: campus.id).order(:name))
      render component, status: status
    end
  end
end
