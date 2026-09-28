# Parameter scrubbing for logs AND for Sentry.
#
# This file did not exist until 2026-09-27, so the ledger was logging every
# request parameter verbatim — including `signature`, and any `private_key` or
# `public_key` that reached a controller. Rails writes these to stdout, which
# Docker captures, and `sentry-rails` reuses this same list to scrub events
# before they leave the box. One list, both paths.
#
# Addresses are deliberately NOT filtered: they are public ledger identifiers
# and are the main thing that makes an error report actionable. Amounts and
# credit limits are likewise kept — losing them would make most ledger
# exceptions impossible to diagnose.
Rails.application.config.filter_parameters += %i[
  signature
  signed_payload
  private_key
  private_key_pem
  secret
  seed
  seed_phrase
  recovery_phrase
  token
  jwt
  authorization
  bearer
  api_key
  service_token
  password
  cookie
  set_cookie
]
