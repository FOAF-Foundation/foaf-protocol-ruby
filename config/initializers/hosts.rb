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
