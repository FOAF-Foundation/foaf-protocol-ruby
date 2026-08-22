source "https://rubygems.org"

ruby "~> 3.2"

gem "rails", "~> 7.1"
gem "pg", "~> 1.5"
gem "puma", "~> 6.0"

# Crypto — secp256k1 signature verification
gem "eth", "~> 0.5"

# CORS
gem "rack-cors", "~> 2.0"

# JSON serialization
gem "jbuilder", "~> 2.7"

group :development, :test do
  gem "rspec-rails", "~> 6.0"
  gem "factory_bot_rails", "~> 6.0"
  gem "debug"
end

group :test do
  gem "database_cleaner-active_record", "~> 2.0"
  gem "shoulda-matchers", "~> 5.0"
end
