Rails.application.config.session_store :cookie_store,
  key: '_memflect_session',
  expire_after: 90.days