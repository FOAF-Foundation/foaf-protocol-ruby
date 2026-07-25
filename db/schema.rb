# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2026_07_25_000000) do
  create_table "currency_networks", charset: "utf8mb4", force: :cascade do |t|
    t.string "address", limit: 42, null: false
    t.string "name", null: false
    t.string "symbol", null: false
    t.integer "decimals", default: 2, null: false
    t.integer "capacity_imbalance_fee_divisor", default: 0, null: false
    t.integer "default_interest_rate", default: 0, null: false
    t.boolean "custom_interests", default: false, null: false
    t.boolean "prevent_mediator_interests", default: false, null: false
    t.integer "max_hops", default: 5, null: false
    t.boolean "is_frozen", default: false, null: false
    t.string "owner_address", limit: 42
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["address"], name: "index_currency_networks_on_address", unique: true
    t.index ["symbol"], name: "index_currency_networks_on_symbol", unique: true
  end

  create_table "operations", charset: "utf8mb4", force: :cascade do |t|
    t.string "operation_type", null: false
    t.string "module_name", null: false
    t.bigint "currency_network_id"
    t.string "actor_address", limit: 42, null: false
    t.json "inputs", null: false
    t.bigint "nonce"
    t.text "signature"
    t.string "idempotency_key", limit: 64
    t.string "multi_hop_id", limit: 36
    t.bigint "parent_operation_id"
    t.decimal "fee_amount", precision: 20, scale: 2, default: "0.0"
    t.string "fee_currency", limit: 10
    t.json "fee_distribution"
    t.string "status", default: "applied", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_address"], name: "index_operations_on_actor_address"
    t.index ["currency_network_id", "created_at"], name: "idx_ops_network_time"
    t.index ["currency_network_id"], name: "index_operations_on_currency_network_id"
    t.index ["idempotency_key"], name: "index_operations_on_idempotency_key", unique: true
    t.index ["multi_hop_id"], name: "index_operations_on_multi_hop_id"
    t.index ["operation_type"], name: "index_operations_on_operation_type"
    t.index ["parent_operation_id"], name: "index_operations_on_parent_operation_id"
  end

  create_table "pending_transfers", charset: "utf8mb4", force: :cascade do |t|
    t.bigint "currency_network_id", null: false
    t.string "from_address", limit: 42, null: false
    t.string "to_address", limit: 42, null: false
    t.decimal "value", precision: 20, scale: 2, null: false
    t.decimal "max_fee", precision: 20, scale: 2, default: "0.0", null: false
    t.string "fee_payer", limit: 10, default: "sender", null: false
    t.json "path"
    t.text "extra_data"
    t.string "status", default: "pending", null: false
    t.text "rejected_reason"
    t.datetime "confirmed_at"
    t.datetime "resolved_at"
    t.bigint "nonce"
    t.text "signature"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "idempotency_key", limit: 64
    t.bigint "operation_id"
    t.index ["currency_network_id"], name: "index_pending_transfers_on_currency_network_id"
    t.index ["from_address"], name: "index_pending_transfers_on_from_address"
    t.index ["idempotency_key"], name: "index_pending_transfers_on_idempotency_key", unique: true
    t.index ["operation_id"], name: "index_pending_transfers_on_operation_id"
    t.index ["status"], name: "index_pending_transfers_on_status"
    t.index ["to_address"], name: "index_pending_transfers_on_to_address"
  end

  create_table "protocol_parameters", charset: "utf8mb4", force: :cascade do |t|
    t.string "key", null: false
    t.string "value", null: false
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_protocol_parameters_on_key", unique: true
  end

  create_table "trustline_events", charset: "utf8mb4", force: :cascade do |t|
    t.bigint "operation_id", null: false
    t.bigint "currency_network_id", null: false
    t.string "event_type", null: false
    t.string "from_address", limit: 42, null: false
    t.string "to_address", limit: 42, null: false
    t.decimal "value", precision: 20, scale: 2
    t.text "extra_data"
    t.decimal "creditline_given", precision: 20, scale: 2
    t.decimal "creditline_received", precision: 20, scale: 2
    t.integer "interest_rate_given"
    t.integer "interest_rate_received"
    t.boolean "is_frozen"
    t.decimal "balance", precision: 20, scale: 2
    t.json "path"
    t.string "fee_payer", limit: 10
    t.decimal "total_fees", precision: 20, scale: 2
    t.json "fees_paid"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["currency_network_id", "event_type", "created_at"], name: "idx_events_network_type_time"
    t.index ["currency_network_id"], name: "index_trustline_events_on_currency_network_id"
    t.index ["event_type"], name: "index_trustline_events_on_event_type"
    t.index ["from_address", "event_type"], name: "idx_events_from_type"
    t.index ["from_address"], name: "index_trustline_events_on_from_address"
    t.index ["operation_id"], name: "index_trustline_events_on_operation_id"
    t.index ["to_address", "event_type"], name: "idx_events_to_type"
    t.index ["to_address"], name: "index_trustline_events_on_to_address"
  end

  create_table "trustline_update_requests", charset: "utf8mb4", force: :cascade do |t|
    t.bigint "trustline_id", null: false
    t.decimal "creditline_given", precision: 20, scale: 2, null: false
    t.decimal "creditline_received", precision: 20, scale: 2, null: false
    t.integer "interest_rate_given", default: 0, null: false
    t.integer "interest_rate_received", default: 0, null: false
    t.boolean "is_frozen", default: false, null: false
    t.string "initiator_address", limit: 42, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["trustline_id"], name: "index_trustline_update_requests_on_trustline_id", unique: true
  end

  create_table "trustlines", charset: "utf8mb4", force: :cascade do |t|
    t.bigint "currency_network_id", null: false
    t.string "user_a_address", limit: 42, null: false
    t.string "user_b_address", limit: 42, null: false
    t.decimal "creditline_given", precision: 20, scale: 2, default: "0.0", null: false
    t.decimal "creditline_received", precision: 20, scale: 2, default: "0.0", null: false
    t.integer "interest_rate_given", default: 0, null: false
    t.integer "interest_rate_received", default: 0, null: false
    t.boolean "is_frozen", default: false, null: false
    t.boolean "allow_routing", default: true, null: false
    t.decimal "balance", precision: 20, scale: 2, default: "0.0", null: false
    t.integer "balance_mtime", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["currency_network_id", "user_a_address", "user_b_address"], name: "idx_trustlines_network_user_pair", unique: true
    t.index ["currency_network_id"], name: "index_trustlines_on_currency_network_id"
    t.index ["user_a_address"], name: "index_trustlines_on_user_a_address"
    t.index ["user_b_address"], name: "index_trustlines_on_user_b_address"
  end

  add_foreign_key "operations", "currency_networks"
  add_foreign_key "pending_transfers", "currency_networks"
  add_foreign_key "pending_transfers", "operations"
  add_foreign_key "trustline_events", "currency_networks"
  add_foreign_key "trustline_events", "operations"
  add_foreign_key "trustline_update_requests", "trustlines"
  add_foreign_key "trustlines", "currency_networks"
end
