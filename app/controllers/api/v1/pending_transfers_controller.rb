# frozen_string_literal: true

module Api
  module V1
    class PendingTransfersController < ApiController
      # GET /api/v1/pending_transfers?address=...
      def index
        address = params[:address]
        incoming = PendingTransfer.incoming_for(address)
        outgoing = PendingTransfer.outgoing_for(address)

        render json: {
          incoming: incoming.map { |pt| serialize_pending(pt) },
          outgoing: outgoing.map { |pt| serialize_pending(pt) }
        }
      end

      # GET /api/v1/pending_transfers/:id
      def show
        render json: serialize_pending(PendingTransfer.find(params[:id]))
      end

      # GET /api/v1/pending_transfers/by_idempotency_key?idempotency_key=...
      def by_idempotency_key
        key = params.require(:idempotency_key)
        render json: serialize_pending(PendingTransfer.find_by!(idempotency_key: key))
      end

      # POST /api/v1/pending_transfers
      def create
        return unless verify_signature!(params[:from_address])

        network = CurrencyNetwork.find_by!(address: params[:network_address])
        attributes = {
          currency_network: network,
          from_address: params[:from_address],
          to_address: params[:to_address],
          value: BigDecimal(params[:value].to_s),
          max_fee: BigDecimal((params[:max_fee] || 0).to_s),
          fee_payer: params[:fee_payer] || "sender",
          path: params[:path],
          extra_data: params[:extra_data],
          idempotency_key: params[:idempotency_key].presence,
          status: "pending"
        }

        if attributes[:idempotency_key]
          existing = PendingTransfer.find_by(idempotency_key: attributes[:idempotency_key])
          return render_idempotent_create(existing, attributes) if existing
        end

        pt = begin
          PendingTransfer.create!(attributes)
        rescue ActiveRecord::RecordNotUnique
          existing = PendingTransfer.find_by!(idempotency_key: attributes[:idempotency_key])
          return render_idempotent_create(existing, attributes)
        end

        render json: serialize_pending(pt), status: :created
      end

      # PUT /api/v1/pending_transfers/:id/confirm
      def confirm
        pt = PendingTransfer.find(params[:id])
        return unless verify_signature!(pt.to_address) # receiver confirms

        response = nil
        pt.with_lock do
          if pt.confirmed?
            response = confirmed_response(pt)
            next
          end
          return render_terminal_conflict(pt, "confirm") unless pt.pending?

          # TransferService joins this lock transaction, so the balance change,
          # operation record, and pending-transfer resolution commit atomically.
          result = TransferService.execute(
            network: pt.currency_network,
            sender_address: pt.from_address,
            receiver_address: pt.to_address,
            value: pt.value,
            max_fee: pt.max_fee,
            path: pt.path,
            fee_payer: pt.fee_payer,
            extra_data: pt.extra_data,
            idempotency_key: "pending-transfer:#{pt.id}"
          )

          pt.update!(
            status: "confirmed",
            operation: result[:operation],
            confirmed_at: Time.current,
            resolved_at: Time.current
          )
          response = confirmed_response(pt, total_fees: result[:total_fees])
        end

        render json: response
      end

      # PUT /api/v1/pending_transfers/:id/reject
      def reject
        pt = PendingTransfer.find(params[:id])
        return unless verify_signature!(pt.to_address) # receiver rejects

        pt.with_lock do
          return render json: serialize_pending(pt) if pt.rejected?
          return render_terminal_conflict(pt, "reject") unless pt.pending?

          pt.update!(
            status: "rejected",
            rejected_reason: params[:reason],
            resolved_at: Time.current
          )
        end
        render json: serialize_pending(pt)
      end

      # DELETE /api/v1/pending_transfers/:id
      def cancel
        pt = PendingTransfer.find(params[:id])
        return unless verify_signature!(pt.from_address) # sender cancels

        pt.with_lock do
          return render json: serialize_pending(pt) if pt.cancelled?
          return render_terminal_conflict(pt, "cancel") unless pt.pending?

          pt.update!(
            status: "cancelled",
            resolved_at: Time.current
          )
        end
        render json: serialize_pending(pt)
      end

      private

      def render_idempotent_create(existing, attributes)
        unless existing.matches_request?(attributes)
          return render json: {
            error: "Idempotency key is already attached to a different pending transfer"
          }, status: :conflict
        end

        render json: serialize_pending(existing), status: :ok
      end

      def render_terminal_conflict(pt, action)
        render json: {
          error: "Cannot #{action} a #{pt.status} transfer",
          transfer: serialize_pending(pt)
        }, status: :conflict
      end

      def confirmed_response(pt, total_fees: nil)
        {
          status: "confirmed",
          transfer: serialize_pending(pt),
          operation: pt.operation_id,
          totalFees: total_fees&.to_f || pt.operation&.fee_amount&.to_f || 0.0
        }
      end

      def serialize_pending(pt)
        {
          id: pt.id,
          idempotencyKey: pt.idempotency_key,
          networkAddress: pt.currency_network.address,
          from: pt.from_address,
          to: pt.to_address,
          value: pt.value.to_f,
          maxFee: pt.max_fee.to_f,
          feePayer: pt.fee_payer,
          path: pt.path,
          extraData: pt.extra_data,
          status: pt.status,
          operation: pt.operation_id,
          rejectedReason: pt.rejected_reason,
          confirmedAt: pt.confirmed_at&.iso8601,
          resolvedAt: pt.resolved_at&.iso8601,
          createdAt: pt.created_at.iso8601
        }
      end
    end
  end
end
