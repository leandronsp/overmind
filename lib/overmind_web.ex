defmodule OvermindWeb do
  @moduledoc false

  def static_paths, do: ~w()

  def html do
    quote do
      use Phoenix.Component

      import Phoenix.HTML
      import Phoenix.Controller, only: [get_csrf_token: 0]
      use Phoenix.VerifiedRoutes,
        endpoint: OvermindWeb.Endpoint,
        router: OvermindWeb.Router,
        statics: OvermindWeb.static_paths()
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
