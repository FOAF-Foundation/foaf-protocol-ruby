require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"

Bundler.require(*Rails.groups)

module FoafProtocol
  class Application < Rails::Application
    config.load_defaults 7.2
    config.api_only = true

    # Load protocol library
    config.autoload_paths << Rails.root.join("foaf_trustline/lib")
  end
end
