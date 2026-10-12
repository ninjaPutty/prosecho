module Components
  module Workspace
    class ChurchNextAccounts < Page
      def initialize(query:, actor:)
        @query, @actor = query, actor
      end

      def view_template
        page("ChurchNext accounts", active: :church_next_accounts) do
          h1(class: "text-4xl font-semibold tracking-tight") { "ChurchNext accounts" }
          p(class: "my-4 text-stone-600") do
            plain "Review possible identity matches. Suggestions use names and approved emails, " \
              "not facial recognition. Only people in your current campus scope are shown."
          end
          unless @query.ready?
            p(role: "alert", class: "mb-6 rounded-xl bg-amber-50 p-4 text-amber-900") do
              plain "Approve email in Data decisions, then refresh people from Rock to enable matching."
            end
          end
          if @query.accounts.empty?
            p(class: "#{CARD} p-8") { "No ChurchNext accounts have been submitted yet." }
          end
          div(class: "space-y-6") { @query.accounts.each { |account| account_card(account) } }
          nav(class: "mt-6 flex gap-5", aria_label: "ChurchNext account pages") do
            if @query.page > 1
              a(href: view_context.admin_church_next_accounts_path(page: @query.page - 1)) { "Previous" }
            end
            if @query.page * ChurchNext::ReviewQuery::PAGE_SIZE < @query.total
              a(href: view_context.admin_church_next_accounts_path(page: @query.page + 1)) { "Next" }
            end
          end
        end
      end

      private

      def account_card(account)
        article(class: "#{CARD} overflow-hidden") do
          div(class: "flex flex-wrap items-center gap-4 border-b border-stone-100 p-5") do
            account_photo(account)
            div(class: "min-w-0 flex-1") do
              h2(class: "text-xl font-semibold") { account.display_name }
              p(class: "break-words text-stone-600") { account.email }
              p(class: "mt-1 text-sm text-stone-500") do
                plain account.email_verified? ? "Verified ChurchNext email" : "Email not verified"
              end
            end
            span(class: "rounded-full bg-teal-50 px-3 py-1 text-sm text-teal-800") { account.status.humanize }
          end
          div(class: "space-y-4 p-5") do
            if account.linked?
              delivery = account.link_delivery
              p do
                plain (delivery&.status == "delivered") ? "ChurchNext has confirmed the link." :
                  "Linked in Prosecho. ChurchNext confirmation is pending."
              end
            else
              choices = @query.candidates.fetch(account.id, [])
              if choices.empty?
                p(class: "text-stone-500") do
                  plain "No pending suggestions in your current campus scope. This account remains unlinked."
                end
              end
              choices.each { |candidate| candidate_row(candidate) }
            end
          end
        end
      end

      def account_photo(account)
        div(class: "relative size-16 shrink-0 overflow-hidden rounded-full bg-teal-50") do
          span(class: "flex h-full items-center justify-center font-semibold text-teal-800") do
            plain [account.first_name.first, account.last_name.first].join.upcase
          end
          if @actor.view_photos? && @query.policy.selected_fields.include?("photo") && account.photo_available?
            img(src: view_context.photo_admin_church_next_account_path(account), alt: "", loading: "lazy",
              data_portrait: true, class: "absolute inset-0 h-full w-full object-cover")
          end
        end
      end

      def candidate_row(candidate)
        person = candidate.person_profile
        div(class: "flex flex-wrap items-center gap-4 rounded-xl bg-stone-50 p-4") do
          portrait(Directory::PersonView.new(person: person, actor: @actor, policy: @query.policy))
          div(class: "min-w-0 flex-1") do
            h3(class: "font-semibold") { person.display_name }
            p(class: "break-words text-sm text-stone-600") { person.email.presence || "No email available" }
            p(class: "mt-1 text-xs text-stone-500") do
              plain (candidate.reason == "email") ? "Exact email match - requires review" :
                "Similar name (#{candidate.score}/100) - requires review"
            end
          end
          if person.churchnext_user_id.present?
            p(class: "text-sm text-amber-800") { "Already linked to a ChurchNext account" }
          else
            post_form(action: view_context.match_admin_church_next_candidate_path(candidate)) do
              button(type: "submit", class: BUTTON) { "Match" }
            end
          end
          post_form(action: view_context.reject_admin_church_next_candidate_path(candidate)) do
            button(type: "submit", class: "rounded-xl border border-stone-300 px-4 py-3 text-sm font-semibold") do
              plain "Not match"
            end
          end
        end
      end
    end
  end
end
