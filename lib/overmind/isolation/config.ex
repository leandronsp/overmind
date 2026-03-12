defmodule Overmind.Isolation.Config do
  @moduledoc false

  # Parses .overmind.yml from a project directory.
  # Handles the format from PRD section 8:
  #
  #   services:
  #     web:
  #       command: bundle exec rails s -p $PORT
  #       port: 3000
  #     db:
  #       docker: postgres:16
  #       port: 5432
  #   isolation:
  #     strategy: ports
  #     port_range: 3100-3999
  #
  # No external YAML dep — supports only this specific format.

  # Service map always has :name and :port; may also have :image or :command
  @type service :: %{required(:name) => String.t(), required(:port) => non_neg_integer()}

  @type t :: %{
          services: [service()],
          isolation: %{strategy: atom(), port_range: {non_neg_integer(), non_neg_integer()}}
        }

  @default_isolation %{strategy: :ports, port_range: {3100, 3999}}

  @spec parse(String.t()) :: {:ok, t()} | {:error, term()}
  def parse(project_path) do
    yml_path = Path.join(project_path, ".overmind.yml")

    case File.read(yml_path) do
      {:ok, content} -> {:ok, parse_content(content)}
      {:error, :enoent} -> {:ok, default_config()}
      {:error, reason} -> {:error, reason}
    end
  end

  # Private

  defp default_config do
    %{services: [], isolation: @default_isolation}
  end

  defp parse_content(content) do
    lines = String.split(content, "\n")

    {services_map, isolation_raw} =
      Enum.reduce(lines, {nil, nil, %{}, %{}}, &parse_line/2)
      |> then(fn {_, _, services, isolation} -> {services, isolation} end)

    services =
      services_map
      |> Map.values()
      |> Enum.filter(&Map.has_key?(&1, :port))
      |> Enum.sort_by(& &1.name)

    isolation = Map.merge(@default_isolation, isolation_raw)
    %{services: services, isolation: isolation}
  end

  # State: {section, service_name, services_map, isolation_map}

  defp parse_line(line, state) do
    stripped = String.trim_leading(line)
    indent = String.length(line) - String.length(stripped)
    trimmed = String.trim(stripped)

    cond do
      trimmed == "" or String.starts_with?(trimmed, "#") -> state
      indent == 0 -> handle_root(trimmed, state)
      indent == 2 -> handle_level1(trimmed, state)
      indent == 4 -> handle_level2(trimmed, state)
      true -> state
    end
  end

  defp handle_root(trimmed, {_, _, services, isolation}) do
    section = String.trim_trailing(trimmed, ":")
    {section, nil, services, isolation}
  end

  defp handle_level1(trimmed, {"services", _, services, isolation}) do
    service_name = String.trim_trailing(trimmed, ":")
    services = Map.put_new(services, service_name, %{name: service_name})
    {"services", service_name, services, isolation}
  end

  defp handle_level1(trimmed, {"isolation", _, services, isolation}) do
    isolation = put_isolation_kv(isolation, trimmed)
    {"isolation", nil, services, isolation}
  end

  defp handle_level1(_trimmed, state), do: state

  defp handle_level2(trimmed, {"services", service_name, services, isolation})
       when service_name != nil do
    service = Map.get(services, service_name, %{name: service_name})
    service = put_service_kv(service, trimmed)
    services = Map.put(services, service_name, service)
    {"services", service_name, services, isolation}
  end

  defp handle_level2(_trimmed, state), do: state

  defp put_service_kv(service, trimmed) do
    case String.split(trimmed, ": ", parts: 2) do
      ["port", val] -> Map.put(service, :port, String.to_integer(String.trim(val)))
      ["docker", val] -> Map.put(service, :image, String.trim(val))
      ["command", val] -> Map.put(service, :command, String.trim(val))
      _ -> service
    end
  end

  defp put_isolation_kv(isolation, trimmed) do
    case String.split(trimmed, ": ", parts: 2) do
      ["strategy", val] -> Map.put(isolation, :strategy, String.to_atom(String.trim(val)))
      ["port_range", val] -> Map.put(isolation, :port_range, parse_port_range(String.trim(val)))
      _ -> isolation
    end
  end

  defp parse_port_range(val) do
    case String.split(val, "-") do
      [min, max] -> {String.to_integer(min), String.to_integer(max)}
      _ -> {3100, 3999}
    end
  end
end
