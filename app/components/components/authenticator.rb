module Components
  class Authenticator < Phlex::HTML
    def initialize(user:, message: nil)
      @message = message
      @user = user
    end

    def view_template
      doctype
      html(lang: "en") do
        head do
          meta(charset: "utf-8")
          meta(name: "viewport", content: "width=device-width, initial-scale=1")
          title { "Authenticator verification | Prosecho" }
          link(rel: "stylesheet", href: view_context.asset_path("tailwind.css"))
        end
        body(class: "bg-stone-50 text-stone-900") do
          main(class: "mx-auto max-w-md px-6 py-20") do
            title = @user.authenticator_enabled? ? "Verify your code" : "Set up your authenticator"
            h1(class: "text-3xl font-semibold") { title }
            p(class: "my-4 text-stone-600") do
              if @user.authenticator_enabled?
                plain "Enter the six-digit code from Authy or Microsoft Authenticator."
              else
                plain "In Authy or Microsoft Authenticator, add an account using this setup key:"
              end
            end
            unless @user.authenticator_enabled?
              div(class: "my-6 rounded border bg-white p-4") do
                h2(class: "font-semibold") { "Choose your authenticator app" }
                ul(class: "my-3 list-inside list-disc space-y-2 text-sm") do
                  li { "Authy: choose Add account and scan this QR code." }
                  li { "Microsoft Authenticator: add Other account and scan this QR code." }
                end
                png = RQRCode::QRCode.new(@user.authenticator_provisioning_uri).as_png(size: 280)
                img(src: "data:image/png;base64,#{Base64.strict_encode64(png.to_s)}",
                  alt: "Prosecho authenticator enrollment QR code", width: 280, height: 280,
                  class: "mx-auto max-w-full")
              end
              p { "Or enter this setup key manually:" }
              p(class: "my-4 break-all rounded border bg-white p-3 font-mono text-sm") do
                plain @user.authenticator_setup_key
              end
              p(class: "my-4 text-sm text-stone-600") do
                plain "Add an account manually for #{@user.email}. Use a time-based code and Prosecho as"
                plain " the issuer."
              end
            end
            if @user.authenticator_enabled?
              form(action: view_context.authenticator_path, method: "post", class: "mt-8 space-y-4") do
                input(type: "hidden", name: "authenticity_token", value: view_context.form_authenticity_token)
                label(for: "recovery_code", class: "block") { "Lost your phone? Use a recovery code" }
                input(id: "recovery_code", name: "recovery_code", type: "text", autocomplete: "off",
                  required: true, class: "w-full rounded border p-3")
                button(type: "submit", class: "rounded border px-4 py-3") { "Enroll a new phone" }
              end
            end
            p(role: "alert", class: "my-4 text-red-700") { @message } if @message.present?
            form(action: view_context.authenticator_path, method: "post", class: "space-y-5") do
              input(type: "hidden", name: "authenticity_token", value: view_context.form_authenticity_token)
              if view_context.current_user && !@user.authenticator_enabled?
                label(for: "current_password", class: "block") { "Current password" }
                input(id: "current_password", name: "current_password", type: "password",
                  autocomplete: "current-password", required: true, class: "w-full rounded border p-3")
              end
              label(for: "otp_code", class: "block") { "Six-digit code" }
              input(id: "otp_code", name: "otp_code", type: "text", inputmode: "numeric",
                autocomplete: "one-time-code",
                pattern: "[0-9]{6}", required: true, class: "w-full rounded border p-3")
              button(type: "submit", class: "w-full rounded bg-teal-800 p-3 text-white") do
                plain @user.authenticator_enabled? ? "Verify and sign in" : "Confirm authenticator"
              end
            end
            p(class: "mt-6 text-sm text-stone-600") do
              plain "Changed or lost your phone? Contact your administrator to reset your authenticator."
            end
            a(href: view_context.new_user_session_path, class: "mt-4 inline-block underline") do
              plain "Back to sign in"
            end
          end
        end
      end
    end
  end
end
