# frozen_string_literal: true

require "rails_helper"

# Wire-contract proof for the one-address-per-identity custodian (spec W5,
# AC 5). The custodian in foaf-auth signs an exact body with
# Eth::Key#personal_sign; the protocol accepts it via the REAL
# SignatureVerifier.verify_by_address path (recover -> derive address ->
# compare) when signature_enforcement is on. This spec builds a keypair
# directly with Eth::Key.new — the same primitive the custodian uses,
# pinned to eth 0.5.17 across both bundles — signs a body, and posts it to
# /api/v1/pending_transfers under enforcement, proving:
#
#   1. A body signed by the from_address key is ACCEPTED (201).
#   2. A body signed by a DIFFERENT key is REJECTED (401).
#
# This does not call the auth custodian; it exercises the protocol side of
# the contract with a locally-built signature, byte-for-byte the shape the
# custodian produces. If this holds, the whole feature's wire contract
# holds under real enforcement.
RSpec.describe "Custodian wire contract", type: :request do
  let(:sender_key) { Eth::Key.new }
  let(:receiver_key) { Eth::Key.new }
  let(:wrong_key) { Eth::Key.new }

  let(:network) do
    CurrencyNetwork.create!(
      address: "0x00000000000000000000000000000000000000c1",
      name: "Custodian Wire Network",
      symbol: "CWN"
    )
  end

  before do
    host! "localhost"
    create_direct_trustline(
      sender_key.address.to_s,
      receiver_key.address.to_s,
      sender_capacity: 100
    )
    # Flip real signature enforcement (exact pattern:
    # pending_transfers_idempotency_spec.rb:123).
    ProtocolParameter.find_or_initialize_by(key: "signature_enforcement").update!(value: "true")
  end

  it "ACCEPTS a pending transfer whose body is signed by the from_address key" do
    body = JSON.generate(
      network_address: network.address,
      from_address: sender_key.address.to_s,
      to_address: receiver_key.address.to_s,
      value: "1",
      idempotency_key: "custodian-wire:accept:1"
    )

    post "/api/v1/pending_transfers",
         params: body,
         headers: signed_headers(sender_key, body)

    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to include("status" => "pending")
  end

  it "REJECTS a pending transfer whose body is signed by the wrong key (401)" do
    body = JSON.generate(
      network_address: network.address,
      from_address: sender_key.address.to_s,
      to_address: receiver_key.address.to_s,
      value: "1",
      idempotency_key: "custodian-wire:reject:1"
    )

    # Signed by wrong_key, but claims from_address = sender_key.
    post "/api/v1/pending_transfers",
         params: body,
         headers: signed_headers(wrong_key, body)

    expect(response).to have_http_status(:unauthorized)
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
