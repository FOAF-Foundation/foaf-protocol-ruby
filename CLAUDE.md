# CLAUDE.md

## Project Overview

Ruby reference implementation of the FOAF protocol — a modular protocol for trust-path-based mutual credit and cooperative goods exchange.

**This is the protocol, not the application.** Growoperative is the first app that consumes it. Other deployments will follow.

### Architecture Document

The full architecture spec is at `../growoperative-app/docs/claude/plans/todo/foaf-protocol-architecture-v3.md`.

### Sibling Projects

| Directory | What |
|-----------|------|
| `../railsbackend/` | Growoperative Rails backend — first consumer of this protocol |
| `../growoperative-app/` | Growoperative React Native app |
| `../trustlines_repositories/` | Trustlines Foundation reference code (contracts, relay, docs, etc.) |

## Design Constraints

### Dual-target architecture

- **API surface → Trustlines Protocol compatible.** The public API maps to Trustlines Protocol semantics. If Growoperative later points at a Trustlines relay on Gnosis, the app barely notices.
- **Internal structure → Radix/Scrypto portable.** Implementation organized so porting to Scrypto blueprints is natural — component-oriented state, per-hop operations composed by a coordinator, pure protocol math as standalone functions.

### Rust extraction readiness

Phase 1 is all Ruby. But pure protocol math must live in `protocol/` with zero Rails/ActiveRecord dependencies — plain values in, plain values out. This layer is lined up for future extraction to Rust/Scrypto. The services layer handles DB transactions, locking, persistence and calls into `protocol/` for the math.

## Repository Structure

```
foaf-protocol-ruby/
  foaf_trustline/              # first protocol module (Rails engine / gem)
    lib/foaf/trustline/
      protocol/                # pure Ruby, NO Rails deps — future Rust extraction
        balance_math.rb        # _applyDirectTransfer equivalent
        trustline_state_machine.rb
        multi_hop_executor.rb
        credloop_detector.rb
        fee_calculator.rb
      models/                  # ActiveRecord models
      services/                # orchestration, locking, persistence
      api/                     # Trustlines-compatible API endpoints
    app/                       # Rails engine conventional dirs
      models/foaf/trustline/
      controllers/foaf/trustline/
    config/
    spec/
  specs/                       # language-agnostic reference specs + test vectors
  docs/
```

### The protocol/ rule

**Nothing in `protocol/` may import ActiveRecord, Rails, or any database concern.** These are pure functions and state machines that take values and return values. They must be testable without a database. This is the boundary for future Rust extraction.

### The specs/ directory

Language-agnostic reference specifications for core protocol primitives. Each spec includes:
- Prose description
- Pseudocode
- Mathematical invariants
- Test vectors (inputs → expected outputs)
- References to Trustlines Foundation equivalents

Any implementation (Ruby, Rust, Scrypto) must satisfy the same test vectors.

## Module Plan

| Module | Status | Description |
|--------|--------|-------------|
| `foaf_trustline` | Phase 1 | Currency networks, trustlines, payments, multi-hop, credloops |
| `foaf_supply_chain` | Future | Request contracts, orders, settlement — optional integration with trustline module |

## Identity and Authentication

FOAF uses blockchain-style cryptographic identity:

- **Identity = public key.** Users are identified by their public key (secp256k1, Ethereum-compatible addresses). FOAF stores only public keys.
- **Auth = signature verification.** Every write operation is signed by the caller's private key. FOAF verifies the signature against the stored public key. No passwords, no sessions.
- **Reads are public.** No auth needed for queries.
- **FOAF never holds private keys.** The calling app is the custodial wallet.

Consuming apps (like Growoperative) store both the public and private key per user. They sign operations on behalf of users. The signing logic in the consuming app must be its own isolated, swappable module — it will be replaced with actual wallet signing later.

## Development

FOAF is a standalone service with its own database. Consuming apps call it over HTTP.

```
Growoperative (Rails)  ──HTTP──▶  FOAF Protocol (Rails, own Postgres DB)
```

### Docker

FOAF runs as its own service in Docker, alongside the Growoperative backend.

### Testing

- `protocol/` tests: pure unit tests, no database, no Rails boot
- `models/` and `services/` tests: integration tests requiring database
- `specs/` test vectors: verified by both Ruby specs and (future) Rust tests
