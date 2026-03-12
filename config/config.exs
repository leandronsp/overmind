import Config

config :overmind, OvermindWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  # Dev-only hardcoded secret — replace with env var for any shared deployment
  secret_key_base: "2bKRfWQ6V5ZON3mFUv8pJyAhLTqcXeI0dYsRgwHzPmCxBaOuEjSkDnlGtFiWrYbQ9K",
  live_view: [signing_salt: "overmind_lv"],
  pubsub_server: Overmind.PubSub,
  check_origin: false,
  render_errors: [formats: [html: OvermindWeb.ErrorHTML], layout: false],
  server: true

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
