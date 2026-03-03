defmodule Overmind.Isolation.Docker do
  @moduledoc false

  # Service spec: %{name: "db", image: "postgres:16", port: 5432}
  # The `port` field is the container's internal port.
  # Pass `host_port: N` in the spec to override the host-side port mapping.
  # When host_port is absent, the declared port is used for both sides.

  @spec start(String.t(), map()) :: {:ok, String.t()} | {:error, String.t()}
  def start(mission_id, service_spec) do
    name = Map.fetch!(service_spec, :name)
    image = Map.fetch!(service_spec, :image)
    container_port = Map.fetch!(service_spec, :port)
    host_port = Map.get(service_spec, :host_port, container_port)

    container_name = container_name(mission_id, name)
    port_mapping = "#{host_port}:#{container_port}"

    case System.cmd("docker", ["run", "-d", "--name", container_name, "-p", port_mapping, image],
           stderr_to_stdout: true
         ) do
      {container_id, 0} -> {:ok, String.trim(container_id)}
      {output, _} -> {:error, String.trim(output)}
    end
  end

  @spec stop(String.t()) :: :ok
  def stop(mission_id) do
    mission_id
    |> list()
    |> Enum.each(fn name ->
      System.cmd("docker", ["rm", "-f", name], stderr_to_stdout: true)
    end)

    :ok
  end

  @spec list(String.t()) :: [String.t()]
  def list(mission_id) do
    prefix = container_prefix(mission_id)

    case System.cmd("docker", ["ps", "-a", "--format", "{{.Names}}", "--filter", "name=#{prefix}"],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        # Docker --filter name= does substring match, so filter precisely
        |> Enum.filter(&String.starts_with?(&1, prefix))

      _ ->
        []
    end
  end

  # Private

  defp container_name(mission_id, service_name) do
    # Use first 8 chars of mission_id to stay within Docker name length limits
    short_id = String.slice(mission_id, 0, 8)
    "#{container_prefix(short_id)}#{service_name}"
  end

  defp container_prefix(mission_id) do
    "overmind-#{mission_id}-"
  end
end
