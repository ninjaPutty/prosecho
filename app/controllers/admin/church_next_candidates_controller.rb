module Admin
  class ChurchNextCandidatesController < BaseController
    def match
      ChurchNext::Linker.new.match!(candidate: candidate, actor: current_user)
      redirect_to admin_church_next_accounts_path, notice: "Account linked. ChurchNext notification is queued.",
        status: :see_other
    rescue ChurchNext::Linker::Conflict => error
      redirect_to admin_church_next_accounts_path, alert: error.message, status: :see_other
    end

    def reject
      ChurchNext::Linker.new.reject!(candidate: candidate, actor: current_user)
      redirect_to admin_church_next_accounts_path, notice: "Not a match. This pair will not be suggested again.",
        status: :see_other
    rescue ChurchNext::Linker::Conflict => error
      redirect_to admin_church_next_accounts_path, alert: error.message, status: :see_other
    end

    private

    def candidate
      ChurchNextCandidate.visible_to(current_user).find(params[:id])
    end
  end
end
