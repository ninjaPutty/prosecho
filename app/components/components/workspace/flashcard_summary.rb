module Components
  module Workspace
    class FlashcardSummary < Phlex::HTML
      def initialize(days:)
        @days = days
      end

      def view_template
        return if @days.empty?

        section(class: "mb-7 space-y-4", aria_label: "Flashcard practice") do
          @days.each do |day|
            article(class: "flex w-full flex-col gap-3 rounded-2xl border border-stone-200 " \
              "bg-white p-5 shadow-sm sm:flex-row sm:items-center sm:justify-between") do
              h2(class: "font-semibold") { "Flashcards - #{day[:day].strftime("%b %-d, %Y")}" }
              div(class: "sm:text-right") do
                p { "#{day[:attempted]} people tried across #{day[:runs]} runs" }
                p(class: "mt-1 text-sm text-stone-600") do
                  plain "#{day[:completion]}% complete / #{day[:accuracy]}% correct"
                end
              end
            end
          end
        end
      end
    end
  end
end
