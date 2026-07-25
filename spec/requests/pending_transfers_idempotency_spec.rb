# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Pending transfer idempotency", type: :request do
  let(:network) do
    CurrencyNetwork.create!(
      address: "0x0000000000000000000000000000000000000001",
      name: "Test Network",
      symbol: "TST"
    )
  end
  let(:sender) { "0x0000000000000000000000000000000000000002" }
  let(:receiver) { "0x0000000000000000000000000000000000000003" }
  let(:idempotency_key) { "test:pending-transfer:1" }
  let(:payload) do
    {
      network_address: network.address,
      from_address: sender,
      to_address: receiver,
      value: "7.5",
      extra_data: { source: "idempotency-spec" }.to_json,
      idempotency_key: idempotency_key
    }
  end

  before do
    host! "localhost"
    ProtocolParameter.find_or_initialize_by(key: "signature_enforcement").update!(value: "false")
    create_direct_trustline(sender, receiver, sender_capacity: 100)
  end

  it "returns the same pending transfer for a retried create" do
    post "/api/v1/pending_transfers", params: payload, as: :json
    first = response.parsed_body

    expect(response).to have_http_status(:created)

    post "/api/v1/pending_transfers", params: payload, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("id")).to eq(first.fetch("id"))
    expect(PendingTransfer.where(idempotency_key: idempotency_key).count).to eq(1)
  end

  it "treats a retried sub-cent value as the same persisted decimal intent" do
    precise_payload = payload.merge(value: "7.505")
    post "/api/v1/pending_transfers", params: precise_payload, as: :json
    first = response.parsed_body

    expect(response).to have_http_status(:created)

    post "/api/v1/pending_transfers", params: precise_payload, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("id")).to eq(first.fetch("id"))
    expect(PendingTransfer.where(idempotency_key: idempotency_key).count).to eq(1)
  end

  it "rejects reuse of an idempotency key for different wire intent" do
    post "/api/v1/pending_transfers", params: payload, as: :json
    post "/api/v1/pending_transfers", params: payload.merge(value: "8.0"), as: :json

    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch("error")).to include("different pending transfer")
    expect(PendingTransfer.where(idempotency_key: idempotency_key).count).to eq(1)
  end

  it "does not apply a retried confirm twice" do
    post "/api/v1/pending_transfers", params: payload, as: :json
    pending_id = response.parsed_body.fetch("id")

    put "/api/v1/pending_transfers/#{pending_id}/confirm", params: {}, as: :json
    first = response.parsed_body
    balance_after_first = trustline.reload.balance

    expect(response).to have_http_status(:ok)

    put "/api/v1/pending_transfers/#{pending_id}/confirm", params: {}, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("operation")).to eq(first.fetch("operation"))
    expect(trustline.reload.balance).to eq(balance_after_first)
    expect(Operation.where(operation_type: "transfer").count).to eq(1)
  end

  it "exposes the resolved operation through both reconciliation reads" do
    post "/api/v1/pending_transfers", params: payload, as: :json
    pending_id = response.parsed_body.fetch("id")
    put "/api/v1/pending_transfers/#{pending_id}/confirm", params: {}, as: :json
    operation_id = response.parsed_body.fetch("operation")

    get "/api/v1/pending_transfers/#{pending_id}"
    expect(response.parsed_body).to include(
      "id" => pending_id,
      "status" => "confirmed",
      "operation" => operation_id
    )

    get "/api/v1/pending_transfers/by_idempotency_key",
        params: { idempotency_key: idempotency_key }
    expect(response.parsed_body).to include(
      "id" => pending_id,
      "status" => "confirmed",
      "operation" => operation_id
    )
  end

  it "requires the receiver signature for confirm when enforcement is enabled" do
    sender_key = Eth::Key.new
    receiver_key = Eth::Key.new
    signed_network = CurrencyNetwork.create!(
      address: "0x0000000000000000000000000000000000000004",
      name: "Signed Network",
      symbol: "SIG"
    )
    create_direct_trustline(
      sender_key.address.to_s,
      receiver_key.address.to_s,
      sender_capacity: 100,
      network: signed_network
    )
    ProtocolParameter.find_by!(key: "signature_enforcement").update!(value: "true")

    create_body = JSON.generate(
      network_address: signed_network.address,
      from_address: sender_key.address.to_s,
      to_address: receiver_key.address.to_s,
      value: "1",
      idempotency_key: "test:signed-transfer:1"
    )
    post "/api/v1/pending_transfers",
         params: create_body,
         headers: signed_headers(sender_key, create_body)
    pending_id = response.parsed_body.fetch("id")

    confirm_body = "{}"
    put "/api/v1/pending_transfers/#{pending_id}/confirm",
        params: confirm_body,
        headers: signed_headers(sender_key, confirm_body)
    expect(response).to have_http_status(:unauthorized)

    put "/api/v1/pending_transfers/#{pending_id}/confirm",
        params: confirm_body,
        headers: signed_headers(receiver_key, confirm_body)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("status" => "confirmed")
  end

  it "requires the receiver signature for reject and makes a retry idempotent" do
    sender_key = Eth::Key.new
    receiver_key = Eth::Key.new
    signed_network = CurrencyNetwork.create!(
      address: "0x0000000000000000000000000000000000000005",
      name: "Signed Reject Network",
      symbol: "SGR"
    )
    ProtocolParameter.find_by!(key: "signature_enforcement").update!(value: "true")

    create_body = JSON.generate(
      network_address: signed_network.address,
      from_address: sender_key.address.to_s,
      to_address: receiver_key.address.to_s,
      value: "1",
      idempotency_key: "test:signed-reject:1"
    )
    post "/api/v1/pending_transfers",
         params: create_body,
         headers: signed_headers(sender_key, create_body)
    pending_id = response.parsed_body.fetch("id")

    reject_body = JSON.generate(reason: "not accepted")
    put "/api/v1/pending_transfers/#{pending_id}/reject",
        params: reject_body,
        headers: signed_headers(sender_key, reject_body)
    expect(response).to have_http_status(:unauthorized)

    2.times do
      put "/api/v1/pending_transfers/#{pending_id}/reject",
          params: reject_body,
          headers: signed_headers(receiver_key, reject_body)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(
        "status" => "rejected",
        "rejectedReason" => "not accepted"
      )
    end
  end

  def trustline
    Foaf::TrustlineRecord.in_network(network.id).between(sender, receiver).first!
  end

  def create_direct_trustline(from, to, sender_capacity:, network: self.network)
    user_a, user_b = [from, to].sort
    from_is_a = from == user_a
    Foaf::TrustlineRecord.create!(
      currency_network: network,
      user_a_address: user_a,
      user_b_address: user_b,
      creditline_given: from_is_a ? 0 : sender_capacity,
      creditline_received: from_is_a ? sender_capacity : 0,
      balance: 0,
      is_frozen: false
    )
  end

  def signed_headers(key, body)
    {
      "CONTENT_TYPE" => "application/json",
      "HTTP_X_SIGNATURE" => key.personal_sign(body)
    }
  end
end
