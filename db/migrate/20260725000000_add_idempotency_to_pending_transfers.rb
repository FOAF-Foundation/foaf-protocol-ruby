# frozen_string_literal: true

class AddIdempotencyToPendingTransfers < ActiveRecord::Migration[7.1]
  def change
    add_column :pending_transfers, :idempotency_key, :string, limit: 64
    add_reference :pending_transfers, :operation, foreign_key: true

    add_index :pending_transfers, :idempotency_key, unique: true
  end
end
