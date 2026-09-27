# Error tracking for the FOAF ledger.
#
# Inert unless SENTRY_DSN is set, so development, test and CI configure nothing
# and send nothing. The DSN is set only on the production Coolify app.
#
# Context: until 2026-09-27 the entire Rails fleet had no error tracking of any
# kind. An exception went to container stdout under a 10MB/3-file rotation and
# nowhere else, so a 500 on one endpoint was invisible — the health probe only
# catches a dead database, not an application error.
return if ENV["SENTRY_DSN"].to_s.strip.empty?

Sentry.init do |config|
  config.dsn = ENV["SENTRY_DSN"]
  config.environment = ENV.fetch("SENTRY_ENVIRONMENT", Rails.env)

  # Belt and braces with the `return` above: even if a DSN leaks into another
  # tier's env, only production will report.
  config.enabled_environments = %w[production]

  # NEVER turn this on here. This service signs and settles credit between real
  # people; send_default_pii would attach request bodies, headers and user
  # context to every event, which for the ledger means signatures and operation
  # payloads landing in a third-party service.
  config.send_default_pii = false

  # Scrub with the SAME list Rails uses for logs, rather than a second list that
  # can drift out of sync. sentry-rails already applies this, and doing it
  # explicitly here means the guarantee survives a future gem default change.
  parameter_filter = ActiveSupport::ParameterFilter.new(
    Rails.application.config.filter_parameters
  )
  config.before_send = lambda do |event, _hint|
    begin
      data = event.request&.data
      event.request.data = parameter_filter.filter(data) if data.is_a?(Hash)
    rescue StandardError => e
      # A scrubbing failure must never swallow the error being reported, but it
      # must also never let an unscrubbed body through.
      Rails.logger.error("[sentry] before_send scrub failed: #{e.class}")
      event.request.data = { "scrubbed" => "before_send failed" } if event.request
    end
    event
  end

  # Only the sentry logger. The default set includes active_support_logger,
  # whose SQL breadcrumbs carry query values — on a ledger that is balances and
  # addresses attached to every unrelated exception.
  config.breadcrumbs_logger = [:sentry_logger]

  # Errors only. Performance tracing would burn the event quota on a service
  # whose value here is "tell me when something raised". Raise deliberately if
  # tracing is ever actually wanted.
  config.traces_sample_rate = 0.0

  # Lets Sentry group regressions by deploy. Coolify exposes the built commit.
  config.release = ENV["SOURCE_COMMIT"] || ENV["COOLIFY_RESOURCE_UUID"]
end
