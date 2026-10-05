Rails.application.config.session_store :cookie_store,
  key: "_prosecho_session", httponly: true, same_site: :lax,
  secure: Rails.env.production?, expire_after: 30.minutes
