defmodule Overmind.Blueprint.Parser do
  @moduledoc false

  @type agent_spec :: %{
          name: String.t(),
          command: String.t(),
          provider: module(),
          type: atom(),
          cwd: String.t() | nil,
          restart_policy: atom(),
          depends_on: [String.t()]
        }

  @spec parse(String.t()) :: {:ok, [agent_spec()]} | {:error, term()}
  def parse(content) do
    case Toml.decode(content) do
      {:ok, data} -> parse_agents(data)
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_agents(%{"agents" => agents}) when is_map(agents) do
    specs = Enum.map(agents, fn {name, attrs} -> parse_agent(name, attrs) end)
    {:ok, specs}
  end

  defp parse_agents(_), do: {:ok, []}

  defp parse_agent(name, attrs) do
    %{
      name: name,
      command: Map.get(attrs, "command", ""),
      provider: parse_provider(Map.get(attrs, "provider", "raw")),
      type: parse_type(Map.get(attrs, "type", "task")),
      cwd: Map.get(attrs, "cwd"),
      restart_policy: parse_restart(Map.get(attrs, "restart_policy", "never")),
      depends_on: Map.get(attrs, "depends_on", [])
    }
  end

  defp parse_provider("claude"), do: Overmind.Provider.Claude
  defp parse_provider(_), do: Overmind.Provider.Raw

  defp parse_type("session"), do: :session
  defp parse_type(_), do: :task

  defp parse_restart("on-failure"), do: :on_failure
  defp parse_restart("on_failure"), do: :on_failure
  defp parse_restart("always"), do: :always
  defp parse_restart(_), do: :never
end
