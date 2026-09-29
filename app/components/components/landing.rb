module Components
  class Landing < Phlex::HTML
    def view_template
      main(class: "min-h-screen bg-[#f5f3ed] px-6 pt-[min(18vh,8rem)] font-[Georgia,serif] leading-[1.6] text-[#242c27] dark:bg-[#1b2420] dark:text-[#f5f3ed]") do
        div(class: "mx-auto max-w-[46rem]") do
          h1(class: "mb-6 text-[clamp(2.5rem,8vw,4rem)] leading-[1.1] tracking-[-0.04em] font-bold") { "Prosecho" }
          p(class: "mb-4") { "A home for thoughtful writing and conversation." }
          p { "More is coming soon." }
        end
      end
    end
  end
end
