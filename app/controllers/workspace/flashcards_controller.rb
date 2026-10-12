module Workspace
  class FlashcardsController < BaseController
    before_action :require_photo_access

    def answer
      run = current_user.flashcard_runs.find(params[:id])
      card = run.cards.find(params[:card_id])
      practice.answer!(run: run, card: card, option_id: params[:option_id])
      redirect_to workspace_flashcard_path(run, card: card.id), status: :see_other
    rescue Directory::Flashcards::Invalid => error
      redirect_to workspace_flashcards_path, alert: error.message, status: :see_other
    end

    def create
      values = params.require(:practice).permit(:count, campus_ids: [], status_ids: [])
      run = practice.start!(campus_ids: values[:campus_ids], status_ids: values[:status_ids],
        count: values[:count])
      redirect_to workspace_flashcard_path(run), status: :see_other
    rescue Directory::Flashcards::Invalid => error
      render Components::Workspace::Flashcards.new(actor: current_user, practice: practice,
        message: error.message), status: :unprocessable_content
    end

    def index
      render Components::Workspace::Flashcards.new(actor: current_user, practice: practice)
    end

    def show
      run = current_user.flashcard_runs.find(params[:id])
      card = params[:card].present? ? run.cards.where.not(answered_at: nil).find(params[:card]) : run.next_card
      choices = card ? practice.choices_for(run, card) : []
      render Components::Workspace::Flashcards.new(actor: current_user, practice: practice,
        run: run, card: card, choices: choices)
    rescue Directory::Flashcards::Invalid => error
      redirect_to workspace_flashcards_path, alert: error.message
    end

    private

    def practice
      @practice ||= Directory::Flashcards.new(actor: current_user, policy: current_policy)
    end

    def require_photo_access
      allowed = current_user.view_photos? && current_policy.confirmed? &&
        current_policy.selected_fields.include?("photo")
      AccessEvent.create!(actor: current_user, resource: "flashcards",
        outcome: allowed ? "allowed" : "denied")
      head :forbidden unless allowed
    end
  end
end
