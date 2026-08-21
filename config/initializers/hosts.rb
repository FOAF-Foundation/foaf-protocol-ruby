# Allow connections from Docker containers and localhost
Rails.application.config.hosts << "host.docker.internal"
Rails.application.config.hosts << "foaf"
Rails.application.config.hosts << "foaf-testnet"
Rails.application.config.hosts << "foaf-production"
Rails.application.config.hosts << "localhost"

# Production hostnames
Rails.application.config.hosts << "dpi.foaf.io"
Rails.application.config.hosts << "api.foaf.io"

# Beta tier (Contabo): public hostname + the internal Coolify network alias
Rails.application.config.hosts << "bpi.foaf.io"
Rails.application.config.hosts << "foaf-protocol-beta"

# Demo tier (Contabo): temp verification host + the internal Coolify network alias
# (dpi.foaf.io, the final demo host, is already allowed above.)
Rails.application.config.hosts << "dpi-temp.foaf.io"
Rails.application.config.hosts << "foaf-protocol-demo"

# Prod tier (Contabo): temp verification host + the internal Coolify network alias.
# (api.foaf.io, the final prod host, is already allowed above.) The prod backend's
# FOAF_API_URL=http://foaf-protocol-prod:3002 uses this alias for internal ledger calls;
# without it the ledger 403s the backend (Blocked host).
Rails.application.config.hosts << "api-temp.foaf.io"
Rails.application.config.hosts << "foaf-protocol-prod"
