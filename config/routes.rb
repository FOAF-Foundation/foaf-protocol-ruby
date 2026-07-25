Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      # === NETWORKS ===
      resources :networks, param: :address, only: [:index, :show] do
        # Trustlines within a network
        member do
          get "users", to: "networks#users"
          get "trustlines", to: "networks#trustlines"
        end

        # User-scoped within a network
        resources :users, param: :address, only: [] do
          member do
            get "/", to: "network_users#show"
            get "trustlines", to: "network_users#trustlines"
            get "events", to: "network_users#events"
          end

          # Specific trustline between two users
          resources :trustlines, param: :counter_party_address, only: [:show] do
            member do
              get "events", to: "trustline_details#events"
            end
          end
        end

        # Pathfinding
        post "path-info", to: "pathfinding#path_info"
        post "max-capacity-path-info", to: "pathfinding#max_capacity_path_info"
        post "close-trustline-path-info", to: "pathfinding#close_trustline_path_info"

        # Generic operations enumeration (blockchain-style, used by indexers).
        get "operations", to: "operations#index"
      end

      # Single-operation detail with embedded events (eth_getTransactionReceipt
      # analog). Generic — no credloop or analytics awareness in the protocol.
      get "operations/:id", to: "operations#show"

      # === CROSS-NETWORK USER ENDPOINTS ===
      resources :users, param: :address, only: [] do
        member do
          get "trustlines", to: "users#trustlines"
          get "events", to: "users#events"
        end
      end

      # === KEYPAIR GENERATION ===
      post "keypair", to: "meta#keypair"
      post "recover", to: "meta#recover"

      # === TRANSFERS ===
      get "transfers", to: "transfers#show"   # ?transactionHash=...

      # === PENDING TRANSFERS (FOAF addition) ===
      resources :pending_transfers, only: [:index, :show, :create] do
        collection do
          get "by_idempotency_key", to: "pending_transfers#by_idempotency_key"
        end
        member do
          put "confirm", to: "pending_transfers#confirm"
          put "reject", to: "pending_transfers#reject"
          delete "/", to: "pending_transfers#cancel"
        end
      end

      # === TRUSTLINE UPDATES ===
      post "networks/:network_address/trustlines/update",
           to: "trustline_updates#create", as: :trustline_update
      delete "networks/:network_address/trustlines/update/:counter_party_address",
             to: "trustline_updates#cancel", as: :cancel_trustline_update

      # === META ===
      get "version", to: "meta#version"
    end
  end
end
