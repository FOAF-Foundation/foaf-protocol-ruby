# FOAF protocol: Ruby implementation

FOAF (Friend of a Friend) is a protocol for community exchange through mutual credit.
Participants agree how much credit to extend to one another. Payments update balances
along those relationships, including paths through intermediaries who permit routing.

This repository implements the credit ledger as a Rails HTTP service with its own
PostgreSQL database. [GrowOperative](https://growoperative.app), a local-food exchange
application, is its first consumer. The application handles listings and exchange
workflows; this service handles trustlines, transfer calculations and ledger records.

[Protocol documentation](https://docs.foaf.foundation) · [FOAF Foundation](https://foaf.foundation)

## Current scope

The Ruby service is under active development. The repository includes:

- Currency networks and bilateral trustlines, with agreed credit limits.
- Direct and multi-hop transfer calculations, pathfinding and routing fees.
- Pending transfers that the receiver can confirm or reject, and the sender can cancel.
- Idempotency keys for pending-transfer creation and repeatable confirmation.
- Operation records and events for inspecting ledger changes.
- Detection and cancellation of circular debt, called credit loops.

The broader architecture proposes Rust/Scrypto ports and additional protocol modules.
Those are not implemented in this repository. The current service persists to
PostgreSQL; it does not execute transfers on a blockchain.

## A small example

Alice and Bob start with a zero balance. Bob extends Alice a credit limit of 100 units.
Alice pays Bob 25 units for produce. The balance from Alice's perspective becomes -25,
leaving 75 units of available credit. Bob sees the opposite balance, +25.

Run this calculation from the repository root with Ruby, without Rails or a database:

```ruby
require "./foaf_trustline/lib/foaf/trustline/protocol"

math = Foaf::Trustline::Protocol::BalanceMath
balance = math.apply_direct_transfer(
  balance: BigDecimal("0"),
  value: BigDecimal("25"),
  creditline_received: BigDecimal("100")
)

puts balance.to_s("F") # -25.0
puts math.capacity(
  balance: balance,
  creditline_received: BigDecimal("100")
).to_s("F") # 75.0
```

These cases are covered in the [balance math specs](spec/protocol/balance_math_spec.rb).
For a routed payment, each hop must have enough capacity; the protocol layer calculates
the changes and the Rails service persists them together.

## Architecture

```text
Consuming application
        |
        | HTTP /api/v1
        v
Rails controllers
        |
        v
Services: transfer coordination, transactions and row locks
        |                              |
        v                              v
Pure Ruby protocol math          ActiveRecord / PostgreSQL
                                 trustlines, operations, events
```

The boundary is deliberate: protocol calculations take values and return results or
errors. They do not load Rails or access the database. Services handle persistence and
call that math inside database transactions. This lets the calculation specs run alone
and gives a future implementation in another language a set of reference cases.

| Location | Responsibility |
| --- | --- |
| [Pure protocol layer](foaf_trustline/lib/foaf/trustline/protocol/) | Balance math, fees, trustline state transitions, multi-hop calculations and credit-loop detection |
| [Services](app/services/) | Transfer execution, signature verification and credit-loop coordination |
| [Models](app/models/) | Persistent ledger records and protocol parameters |
| [API controllers](app/controllers/api/v1/) | HTTP requests and responses |
| [Routes](config/routes.rb) | Current API surface |
| [Protocol specs](spec/protocol/) | Calculation and state-machine examples without Rails |
| [Request specs](spec/requests/) | API contracts, pending-transfer retries and signature enforcement |

[TransferService](app/services/transfer_service.rb) locks the affected trustlines in
canonical order and writes balance changes, the operation and its events within one
transaction. [Pending-transfer confirmation](app/controllers/api/v1/pending_transfers_controller.rb)
locks the pending record, joins that transaction and returns the existing result when
a confirmed transfer is retried. The [request specs](spec/requests/pending_transfers_idempotency_spec.rb)
exercise that retry behavior.

## Identity and current defaults

Participants are identified by Ethereum-style addresses. The service can recover a
signer's address from a secp256k1 signature supplied in the `X-Signature` header over
the raw request body.

Signature enforcement defaults to off. The `signature_enforcement` protocol parameter
must be set to `"true"` to activate the controller checks. Reads are public. The API also
includes key generation and recovery endpoints that return private key material to the
caller.

See the [API controller](app/controllers/api/v1/api_controller.rb),
[signature verifier](app/services/signature_verifier.rb) and
[key endpoints](app/controllers/api/v1/meta_controller.rb).

## Local development

The Docker setup uses Ruby 3.4.11, Rails 8.1 and PostgreSQL 16. Install Docker with
Compose, then run from the repository root:

```sh
docker compose build foaf
docker compose up -d db
docker compose run --rm foaf bundle exec rails db:prepare
docker compose up -d foaf
curl http://localhost:3002/api/v1/version
```

The API listens on port 3002 and PostgreSQL is mapped to host port 5434. The supplied
Compose file uses development credentials and publishes both ports; use it only in a
trusted local environment. Initial seeds create protocol parameters, not example
currency networks or users.

Stop the local services with `docker compose down`. The named database volume is
retained.

## Tests

After building the image, the pure protocol specs need no database:

```sh
docker compose run --rm --no-deps foaf bundle exec rspec spec/protocol
```

For the complete suite, start the database and prepare the separate test database:

```sh
docker compose up -d db
docker compose run --rm -e RAILS_ENV=test foaf bundle exec rails db:test:prepare
docker compose run --rm -e RAILS_ENV=test foaf bundle exec rspec
```

The test configuration derives a test database URL from the development URL, or accepts
an explicit `DATABASE_URL_TEST`. The [CI workflow](.github/workflows/ci.yml) runs the
complete RSpec suite against PostgreSQL on pull requests.
