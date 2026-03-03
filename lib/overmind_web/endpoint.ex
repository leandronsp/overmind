defmodule OvermindWeb.Endpoint do
  @moduledoc false
  use Phoenix.Endpoint, otp_app: :overmind

  @session_options [
    store: :cookie,
    key: "_overmind_key",
    signing_salt: "overmind_salt",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]]

  # Serve phoenix.js and phoenix_live_view.js from deps priv/static
  plug Plug.Static,
    at: "/js/phoenix",
    from: {:phoenix, "priv/static"},
    gzip: false

  plug Plug.Static,
    at: "/js/lv",
    from: {:phoenix_live_view, "priv/static"},
    gzip: false

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug OvermindWeb.Router
end
