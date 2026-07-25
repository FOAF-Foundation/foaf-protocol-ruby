class PendingTransfer < ApplicationRecord
  belongs_to :currency_network
  belongs_to :operation, optional: true

  validates :from_address, presence: true
  validates :to_address, presence: true
  validates :value, presence: true, numericality: { greater_than: 0 }
  validates :status, presence: true, inclusion: { in: %w[pending confirmed rejected cancelled] }
  validates :fee_payer, inclusion: { in: %w[sender receiver] }
  validates :idempotency_key, length: { maximum: 64 }, allow_nil: true

  scope :pending, -> { where(status: "pending") }
  scope :for_address, ->(addr) { where("from_address = ? OR to_address = ?", addr, addr) }
  scope :incoming_for, ->(addr) { where(to_address: addr, status: "pending") }
  scope :outgoing_for, ->(addr) { where(from_address: addr, status: "pending") }

  def pending?
    status == "pending"
  end

  def confirmed?
    status == "confirmed"
  end

  def rejected?
    status == "rejected"
  end

  def cancelled?
    status == "cancelled"
  end

  def matches_request?(attributes)
      currency_network_id == attributes.fetch(:currency_network).id &&
      from_address.casecmp?(attributes.fetch(:from_address).to_s) &&
      to_address.casecmp?(attributes.fetch(:to_address).to_s) &&
      value == persisted_decimal(:value, attributes.fetch(:value)) &&
      max_fee == persisted_decimal(:max_fee, attributes.fetch(:max_fee)) &&
      fee_payer == attributes.fetch(:fee_payer) &&
      path == attributes.fetch(:path) &&
      extra_data == attributes.fetch(:extra_data)
  end

  private

  def persisted_decimal(attribute, raw_value)
    scale = self.class.columns_hash.fetch(attribute.to_s).scale
    BigDecimal(raw_value.to_s).round(scale)
  end
end
