require "sidekiq/web"

Rails.application.routes.draw do
  root "home#show"
  get "/auth/sign-in", to: "web/auth/sessions#new", as: :browser_sign_in
  post "/auth/sign-in", to: "web/auth/sessions#create"
  post "/auth/sign-out", to: "web/auth/sessions#destroy"
  delete "/auth/sign-out", to: "web/auth/sessions#destroy", as: :browser_sign_out
  get "/auth/sign-up", to: "web/auth/registrations#new", as: :browser_sign_up
  post "/auth/sign-up", to: "web/auth/registrations#create"
  get "/app", to: "home#show", as: :dashboard
  resources :notebooks do
    member do
      patch :archive
      patch :unarchive
    end

    resources :chapters do
      member do
        patch :move
        patch :restore
      end

      resources :pages do
        member do
          patch :move
          delete "photos/:attachment_id", action: :destroy_photo, as: :photo
        end
      end
    end
  end

  resources :notepad_entries, path: "notepad" do
    member do
      delete "photos/:attachment_id", action: :destroy_photo, as: :photo
    end
  end

  get "/capture", to: "capture_studio#show", as: :capture_studio
  get "/inbox", to: "inbox#show", as: :inbox
  resources :projects, only: %i[index create show]
  get "/daily", to: "daily_logs#index", as: :daily_logs
  get "/daily/:date", to: "daily_logs#show", as: :daily_log
  resources :captures, only: %i[show update] do
    member do
      post :extract_text
      post :generate_summary
      post :backup
      get :preview
    end

    resources :attachments, only: :create, controller: "capture_attachments"
    resources :reference_links, only: :create, controller: "capture_reference_links"
    resources :tasks, only: :create, controller: "capture_tasks"
  end
  resources :tasks, only: %i[index create update]
  get "/search", to: "search#index", as: :search_page
  get "/library", to: "library#index", as: :library
  get "/settings", to: "settings#show", as: :settings
  patch "/settings", to: "settings#update"
  get "/onboarding", to: "onboarding#show", as: :onboarding
  get "/install", to: "install#show", as: :install

  namespace :settings do
    resource :backup, only: %i[show update], controller: "backup"
    resource :privacy, only: %i[show update], controller: "privacy"
    resource :drive_connection, only: %i[create update destroy], controller: "drive_connections" do
      post :create_folder, on: :collection
    end
  end

  namespace :admin do
    get "/", to: "dashboard#show", as: :dashboard
    resources :captures, only: :index
    resource :operations, only: :show
    resources :users, only: %i[index update]
    post "/users/:id/role", to: "users#update", as: :user_role
  end

  namespace :internal do
    resources :ocr_jobs, only: [] do
      post :perform, on: :member
    end

    resources :drive_syncs, only: [] do
      post :perform, on: :member
    end
  end

  namespace :api do
    namespace :v1 do
      namespace :auth do
        get :csrf_token, to: "csrf_tokens#show"
        post :sign_up, to: "registrations#create"
        post :sign_in, to: "sessions#create"
        delete :sign_out, to: "sessions#destroy"
      end

      resources :notebooks, only: %i[index create show update destroy]
      resources :projects, only: %i[index create show update]
      resources :daily_logs, only: %i[index show create]
      resources :tasks, only: %i[index create update]
      resources :attachments, only: %i[index create destroy]
      resource :app_setting, only: %i[show update]
      resources :sync_jobs, only: %i[index create]
      resources :tags, only: %i[index create destroy]
      resources :upload_urls, only: :create
      resources :captures, only: %i[index create show update] do
        post :reprocess, on: :member
        post :export_to_drive, on: :member
        post :generate_summary, on: :member
      end
      resource :drive_connection, only: %i[show create update destroy], controller: :drive_connections do
        get :callback, on: :collection
      end

      get :search, to: "searches#index"
    end
  end

  mount Sidekiq::Web => "/sidekiq" if Rails.env.development?
end
