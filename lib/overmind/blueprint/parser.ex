defmodule Overmind.Blueprint.Parser do
  @moduledoc false

  @type agent_spec :: %{
          name: String.t(),
          command: String.t(),
          provider: module(),
          type: :task | :session,
          cwd: String.t() | nil,
          restart_policy: :never | :on_failure | :always,
          depends_on: [String.t()]
        }

  @spec parse(String.t()) :: {:ok, [agent_spec()]} | {:error, term()}
  def parse(content) do
    case Toml.decode(content) do
      {:ok, decoded} ->
        agents_map = Map.get(decoded, "agents", %{})
        specs = build_specs(agents_map)
        validate_specs(specs)

      {:error, reason} ->
        {:error, {:invalid_toml, reason}}
    end
  end

  defp build_specs(agents_map) do
    Enum.map(agents_map, fn {name, config} ->
      %{
        name: name,
        command: Map.get(config, "command"),
        provider: parse_provider(Map.get(config, "provider", "raw")),
        type: parse_type(Map.get(config, "type", "task")),
        cwd: Map.get(config, "cwd"),
        restart_policy: parse_restart(Map.get(config, "restart", "never")),
        depends_on: Map.get(config, "depends_on", [])
      }
    end)
  end

  defp validate_specs(specs) do
    with :ok <- validate_commands(specs),
         :ok <- validate_dependencies(specs) do
      {:ok, specs}
    end
  end

  defp validate_commands(specs) do
    case Enum.find(specs, fn spec -> is_nil(spec.command) end) do
      nil -> :ok
      spec -> {:error, {:missing_command, spec.name}}
    end
  end

  defp validate_dependencies(specs) do
    names = MapSet.new(specs, & &1.name)

    Enum.reduce_while(specs, :ok, fn spec, :ok ->
      case Enum.find(spec.depends_on, fn dep -> not MapSet.member?(names, dep) end) do
        nil -> {:cont, :ok}
        dep -> {:halt, {:error, {:unknown_dependency, spec.name, dep}}}
      end
    end)
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
