Rails.application.routes.draw do
  devise_for :users, only: :sessions, controllers: {sessions: "users/sessions"}
  get "dashboard", to: "dashboard#show"
  namespace :workspace do
    resource :filters, only: %i[create destroy]
    post "refresh", to: "refreshes#create"
    get "refresh/status", to: "refreshes#show", as: :refresh_status
    get "map", to: "views#map"
    get "changes", to: "views#changes"
    resources :people, only: :show do
      get "photo", to: "photos#show"
    end
  end
  namespace :admin do
    root "dashboard#show"
    post "setup", to: "setup#create"
    resources :accounts, only: %i[new create edit update]
    resources :campuses, only: %i[edit update] do
      post :import, on: :collection
    end
    resource :data_policy, only: %i[show update]
  end
  mount Lookbook::Engine, at: "/lookbook" if Rails.env.development?
  root "home#index"
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up", to: "rails/health#show", as: :rails_health_check
  get "ready", to: "readiness#show"

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
