# frozen_string_literal: true

# Transfer execution — direct and multi-hop.
# Like calling transfer() on a Scrypto CurrencyNetwork component.
# All balance mutations are atomic with row-level locking.

class TransferService
  # Execute a transfer (direct or multi-hop).
  # Mirrors CurrencyNetworkBasic.transfer / _mediatedTransferSenderPays
  #
  # @param network [CurrencyNetwork]
  # @param sender_address [String]
  # @param receiver_address [String]
  # @param value [BigDecimal] amount to transfer
  # @param max_fee [BigDecimal] maximum acceptable fee
  # @param path [Array<String>] ordered addresses from sender to receiver
  # @param fee_payer [String] "sender" or "receiver"
  # @param extra_data [String, nil] app-specific metadata (JSON)
  # @param idempotency_key [String, nil] unique write key supplied by the caller
  # @return [Hash] { operation:, events:, total_fees:, path: }
  def self.execute(network:, sender_address:, receiver_address:, value:,
                   max_fee: BigDecimal("0"), path: nil, fee_payer: "sender",
                   extra_data: nil, idempotency_key: nil)
    raise "Network is frozen" if network.frozen?
    raise "Value must be positive" unless value > 0

    # Default to direct path if none provided
    path ||= [sender_address, receiver_address]

    # Validate path
    validation = Foaf::Trustline::Protocol::MultiHopExecutor.validate_path(path)
    raise validation[:reason] unless validation[:valid]
    raise "Path must start with sender" unless path.first == sender_address
    raise "Path must end with receiver" unless path.last == receiver_address

    multi_hop_id = SecureRandom.uuid if path.size > 2

    ActiveRecord::Base.transaction do
      # Load all trustlines in path order, lock in canonical ID order to prevent deadlock
      trustline_pairs = path.each_cons(2).map { |a, b| [a, b] }
      trustlines = load_and_lock_trustlines(network, trustline_pairs)

      # Build hop data for the protocol layer
      hops = trustline_pairs.map do |sender, receiver|
        tl = trustlines[[sender, receiver].sort]
        raise "No trustline between #{sender} and #{receiver}" unless tl

        # Check routing consent for intermediaries
        if sender != path.first && sender != path.last
          raise "User #{sender} has disabled routing" unless tl.allow_routing
        end
        if receiver != path.first && receiver != path.last
          raise "User #{receiver} has disabled routing" unless tl.allow_routing
        end

        sender_is_a = tl.user_is_a?(sender)
        balance = Foaf::Trustline::Protocol::BalanceMath.balance_for_user(
          balance: tl.balance, user_is_a: sender_is_a
        )
        creditline_received = Foaf::Trustline::Protocol::BalanceMath.creditline_received_for_user(
          creditline_a_to_b: tl.creditline_given,
          creditline_b_to_a: tl.creditline_received,
          user_is_a: sender_is_a
        )

        {
          sender: sender,
          receiver: receiver,
          balance: balance,
          creditline_received: creditline_received,
          trustline: tl,
          sender_is_a: sender_is_a
        }
      end

      # Execute through protocol layer (pure math, no DB)
      result = if fee_payer == "sender"
        Foaf::Trustline::Protocol::MultiHopExecutor.execute_sender_pays(
          hops: hops.map { |h| h.slice(:sender, :receiver, :balance, :creditline_received) },
          value: value,
          max_fee: max_fee,
          capacity_imbalance_fee_divisor: network.capacity_imbalance_fee_divisor
        )
      else
        Foaf::Trustline::Protocol::MultiHopExecutor.execute_receiver_pays(
          hops: hops.map { |h| h.slice(:sender, :receiver, :balance, :creditline_received) },
          value: value,
          max_fee: max_fee,
          capacity_imbalance_fee_divisor: network.capacity_imbalance_fee_divisor
        )
      end

      # Record the top-level operation
      op = Operation.create!(
        operation_type: "transfer",
        module_name: "trustline",
        currency_network: network,
        actor_address: sender_address,
        inputs: {
          from: sender_address,
          to: receiver_address,
          value: value.to_f,
          max_fee: max_fee.to_f,
          path: path,
          fee_payer: fee_payer
        },
        idempotency_key: idempotency_key,
        multi_hop_id: multi_hop_id,
        fee_amount: result[:total_fees],
        status: "applied"
      )

      # Apply balance changes and emit events
      events = []
      fees_paid = []

      result[:hop_results].each_with_index do |hop_result, index|
        hop_data = hops[index]
        tl = hop_data[:trustline]

        # Convert new_balance back to canonical (user_a perspective)
        canonical_new_balance = if hop_data[:sender_is_a]
          hop_result[:new_balance]
        else
          -hop_result[:new_balance]
        end

        # Update trustline balance
        tl.update!(balance: canonical_new_balance)

        fees_paid << hop_result[:fee].to_f

        # Emit BalanceUpdate event per hop
        events << TrustlineEvent.create!(
          operation: op,
          currency_network: network,
          event_type: "BalanceUpdate",
          from_address: hop_result[:sender],
          to_address: hop_result[:receiver],
          balance: canonical_new_balance
        )
      end

      # Emit Transfer event (endpoint to endpoint)
      transfer_event = TrustlineEvent.create!(
        operation: op,
        currency_network: network,
        event_type: "Transfer",
        from_address: sender_address,
        to_address: receiver_address,
        value: value,
        extra_data: extra_data,
        path: path,
        fee_payer: fee_payer,
        total_fees: result[:total_fees],
        fees_paid: fees_paid
      )
      events << transfer_event

      transfer_result = {
        operation: op,
        events: events,
        total_fees: result[:total_fees],
        path: path,
        value: value
      }

      # Trigger credloop detection after every transfer (debounced)
      # Skip if this transfer IS a credloop cancellation (avoid infinite loop)
      unless extra_data&.include?("credloop_cancellation")
        CredloopRunner.trigger(network)
      end

      transfer_result
    end
  end

  private

  # Load trustlines for all pairs in the path, locked in canonical ID order.
  # Canonical lock ordering prevents deadlocks on concurrent multi-hop transfers.
  def self.load_and_lock_trustlines(network, pairs)
    # Sort pairs canonically for deterministic lock ordering
    canonical_pairs = pairs.map { |a, b| [a, b].sort }.uniq
    canonical_pairs.sort_by! { |a, b| [a, b] }

    trustlines = {}
    canonical_pairs.each do |a, b|
      tl = Foaf::TrustlineRecord
        .in_network(network.id)
        .where(user_a_address: a, user_b_address: b)
        .lock("FOR UPDATE")
        .first

      trustlines[[a, b]] = tl
    end

    trustlines
  end
end
