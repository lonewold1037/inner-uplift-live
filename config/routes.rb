# config/routes.rb
Rails.application.routes.draw do
  # Health check for uptime monitoring
  get "up" => "rails/health#show", as: :rails_health_check

  # PWA routes
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Mount ActionCable for WebSocket connections
  mount ActionCable.server => '/cable'

  # Stripe webhook (must be at top level, not nested)
  post "webhooks/stripe", to: "stripe_webhooks#create"

  # Public homepage
  root "pages#home"

  # Public pages
  get "privacy", to: "pages#privacy"
  get "terms", to: "pages#terms"

  # User dashboard
  get "dashboard", to: "users#dashboard"

  # Audio download routes
  get 'reflections/:id/preview_audio', to: 'downloads#preview_audio', as: 'preview_audio'
  get 'reflections/:id/extended_audio', to: 'downloads#extended_audio', as: 'extended_audio'

  # Devise routes for authentication
  devise_for :users

  # Reflection feature routes
  resources :reflections, only: [:new, :create, :show] do
    member do
      # Page where the user speaks their mantra
      get  "record"

      # Action that receives the uploaded audio from the recording page
      post "receive_audio"

      # Action that receives the chosen soundscape and starts the mixing job
      post "mix_audio"
      
      # Action that changes/swaps out the soundscape .mp3 for different on final playback page
      post "remix_audio"

      # Stripe checkout for extended version
      post "checkout"
    end
  end

  # Optional browse routes for soundscapes
  resources :soundscapes, only: [:index, :show]
end
