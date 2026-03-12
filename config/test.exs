import Config

# Disable HTTP server in tests — LiveViewTest bypasses HTTP directly
config :overmind, OvermindWeb.Endpoint,
  http: [port: 4002],
  server: false
