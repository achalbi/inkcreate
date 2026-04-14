require "sidekiq/web"

Rails.application.routes.draw do
  root "home#show"
  get "/privacy-policy", to: "legal#privacy_policy", as: :privacy_policy
  get "/terms-of-service", to: "legal#terms_of_service", as: :terms_of_service
  get "/auth/sign-in", to: "web/auth/sessions#new", as: :browser_sign_in
  post "/auth/sign-in", to: "web/auth/sessions#create"
  post "/auth/sign-out", to: "web/auth/sessions#destroy"
  delete "/auth/sign-out", to: "web/auth/sessions#destroy", as: :browser_sign_out
  post "/auth/google", to: "web/auth/google#create", as: :browser_google_auth
  get "/auth/google/callback", to: "web/auth/google#callback", as: :browser_google_auth_callback
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

        scope module: :pages do
          resource :todo_list, only: %i[create update]
          resources :todo_items, only: %i[create update destroy] do
            member do
              patch :toggle
              patch :reorder
            end
          end
          resources :voice_notes,       only: %i[create destroy] do
            post :submit_transcript, on: :member
          end
          resources :scanned_documents, only: %i[create destroy] do
            post :extract_text, on: :member
            post :submit_ocr_result, on: :member
            get :ocr_source, on: :member
          end
        end
      end
    end
  end

  resources :notepad_entries, path: "notepad" do
    collection do
      post :quick_create
    end

    member do
      delete "photos/:attachment_id", action: :destroy_photo, as: :photo
    end

    scope module: :notepad_entries do
      resource :todo_list, only: %i[create update]
      resources :todo_items, only: %i[create update destroy] do
        member do
          patch :toggle
          patch :reorder
        end
      end
      resources :voice_notes,       only: %i[create destroy] do
        post :submit_transcript, on: :member
      end
      resources :scanned_documents, only: %i[create destroy] do
        post :extract_text, on: :member
        post :submit_ocr_result, on: :member
        get :ocr_source, on: :member
      end
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
  resources :tasks, only: %i[index show create update destroy] do
    collection do
      get  :link_search
      post :promote_from_todo
    end
    member do
      patch :toggle_complete
    end
    resources :task_subtasks, only: %i[create update destroy], shallow: true
  end
  resources :reminders, only: %i[index show edit create update destroy] do
    member do
      patch :dismiss
      patch :snooze
    end
  end
  resources :devices, only: %i[index destroy] do
    member do
      post :enable_push
      delete :disable_push
    end
  end
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

    resources :reminders, only: [] do
      post :perform, on: :member
    end

    resources :drive_syncs, only: [] do
      post :perform, on: :member
    end

    resources :google_drive_exports, only: [] do
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
