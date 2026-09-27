#!/bin/bash
set -e

# Run DB migrations on production boot. Idempotent: a no-op when the schema is
# already up to date, so redeploys of an already-migrated tier are safe. This is
# how the tier's ledger schema gets created on a fresh Neon DB (Contabo tiers).
if [ "${RAILS_ENV}" = "production" ]; then
  echo "==> foaf-protocol: bundle exec rails db:migrate"
  bundle exec rails db:migrate
fi

exec "$@"
