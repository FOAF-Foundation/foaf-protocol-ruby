FROM ruby:3.2-slim

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    build-essential \
    libpq-dev \
    git \
    pkg-config \
    libsecp256k1-dev \
    libyaml-dev \
    automake \
    libtool \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock* ./
RUN bundle install

COPY . .

RUN chmod +x docker-entrypoint.sh

EXPOSE 3002

# Entrypoint runs db:migrate on production boot (idempotent), then execs CMD.
ENTRYPOINT ["./docker-entrypoint.sh"]
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3002"]
