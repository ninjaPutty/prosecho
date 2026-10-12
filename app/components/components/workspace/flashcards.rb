module Components
  module Workspace
    class Flashcards < Page
      def initialize(actor:, practice:, run: nil, card: nil, choices: [], message: nil)
        @actor, @practice, @run, @card, @choices, @message = actor, practice, run, card, choices, message
      end

      def view_template
        page("Flashcards", active: :flashcards) do
          h1(class: "text-4xl font-semibold tracking-tight") { "Flashcards" }
          p(class: "my-4 text-stone-600") do
            plain "Practice remembering names. Missed names return sooner; familiar names are spaced further apart."
          end
          p(role: "alert", class: "mb-4 text-red-800") { @message } if @message
          @run ? exercise : setup_form
        end
      end

      private

      def exercise
        p(class: "my-4") { "#{@run.completion}% complete" }
        unless @card
          h2(class: "text-2xl font-semibold") { "Practice complete" }
          p(class: "my-4") do
            plain "#{@run.cards.where(correct: true).count} of #{@run.planned_count} names recalled correctly."
          end
          a(href: view_context.workspace_flashcards_path, class: BUTTON) { "Start another run" }
          return
        end
        div(class: "#{CARD} mx-auto max-w-2xl space-y-5 p-6") do
          p(class: "text-sm text-stone-500") { "Person #{@card.position} of #{@run.planned_count}" }
          img(src: view_context.workspace_person_photo_path(@card.person_profile),
            alt: "Who is this person?", class: "mx-auto size-64 rounded-2xl object-cover")
          if @card.answered_at
            p(role: "status", class: "text-lg font-semibold") do
              plain @card.correct? ? "Correct! " : "Not quite. "
              plain "This is #{@card.person_profile.display_name}."
            end
            a(href: view_context.workspace_flashcard_path(@run), class: BUTTON) { "Continue" }
          else
            h2(class: "text-xl font-semibold") { "Which name matches the photo?" }
            post_form(action: view_context.answer_workspace_flashcard_path(@run)) do
              input(type: "hidden", name: "card_id", value: @card.id)
              div(class: "grid gap-3 sm:grid-cols-2") do
                @choices.each do |person|
                  button(type: "submit", name: "option_id", value: person.id,
                    class: "rounded-xl border border-teal-700 p-4 text-teal-900 hover:bg-teal-50") do
                    plain person.display_name
                  end
                end
              end
            end
          end
        end
      end

      def setup_form
        people = @practice.available
        post_form(action: view_context.workspace_flashcards_path) do
          div(class: "#{CARD} max-w-2xl space-y-6 p-6") do
            fieldset do
              legend(class: "mb-3 font-semibold") { "Campuses" }
              @actor.campuses.active.order(:name).each do |campus|
                checkbox("campus_ids", campus.id, campus.name)
              end
            end
            fieldset do
              legend(class: "mb-3 font-semibold") { "Connection statuses" }
              people.distinct.pluck(:connection_status_id, :connection_status_label).each do |id, name|
                checkbox("status_ids", id || "unknown", name || "Unknown")
              end
            end
            label(class: "block") do
              plain "How many people?"
              input(type: "number", name: "practice[count]", min: 1, max: 100,
                value: 10, required: true, class: INPUT)
            end
            p(class: "text-sm text-stone-500") do
              plain "Choose a pool with at least four distinct names and available photos. Up to 100 people per run."
            end
            button(type: "submit", class: BUTTON) { "Start practice" }
          end
        end
      end

      def checkbox(key, value, text)
        label(class: "mb-2 flex items-center gap-3") do
          input(type: "checkbox", name: "practice[#{key}][]", value: value, checked: true)
          plain text
        end
      end
    end
  end
end
