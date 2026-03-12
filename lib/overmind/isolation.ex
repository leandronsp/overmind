defmodule Overmind.Isolation do
  @moduledoc false

  # Orchestrates M4 full isolation lifecycle:
  #   1. Read .overmind.yml config
  #   2. Allocate unique host ports (PortRegistry)
  #   3. Start Docker containers for declared services
  #   4. Create git worktree for the mission
  #   5. Return env vars to inject into the spawned process
  #
  # Teardown is the reverse: stop containers, release ports, remove worktree.

  alias Overmind.Isolation.{Config, Docker, PortRegistry, Worktree}

  @type setup_result :: %{
          worktree_path: String.t(),
          env: [{String.t(), String.t()}]
        }

  @spec setup(String.t(), String.t()) :: {:ok, setup_result()} | {:error, term()}
  def setup(mission_id, project_path) do
    with {:ok, config} <- Config.parse(project_path),
         {:ok, env} <- allocate_and_start(mission_id, config, project_path),
         branch <- "overmind/#{mission_id}",
         {:ok, worktree_path} <- Worktree.create(project_path, branch) do
      {:ok, %{worktree_path: worktree_path, env: env}}
    end
  end

  @spec teardown(String.t(), String.t()) :: :ok
  def teardown(mission_id, project_path) do
    Docker.stop(mission_id)
    PortRegistry.release(mission_id)
    branch = "overmind/#{mission_id}"
    worktree_path = Path.join([project_path, ".overmind", "worktrees", branch])
    Worktree.cleanup(project_path, worktree_path)
    :ok
  end

  # Private

  # Allocate a host port for every service, start docker containers for those
  # with an :image, and build the env var list to inject into the mission.
  defp allocate_and_start(mission_id, config, _project_path) do
    services = config.services
    {min, max} = config.isolation.port_range

    Enum.reduce_while(services, {:ok, []}, fn service, {:ok, acc_env} ->
      case PortRegistry.allocate(mission_id, service.name, min) do
        {:ok, host_port} when host_port <= max ->
          start_docker_if_needed(mission_id, service, host_port)
          env_key = service_env_key(service.name)
          {:cont, {:ok, [{env_key, Integer.to_string(host_port)} | acc_env]}}

        {:ok, _} ->
          # Port allocated but above our range — release and fail
          PortRegistry.release(mission_id)
          {:halt, {:error, :port_range_exhausted}}

        {:error, :exhausted} ->
          PortRegistry.release(mission_id)
          {:halt, {:error, :port_range_exhausted}}
      end
    end)
  end

  defp start_docker_if_needed(_mission_id, service, _host_port)
       when not is_map_key(service, :image),
       do: :ok

  defp start_docker_if_needed(mission_id, service, host_port) do
    spec = Map.put(service, :host_port, host_port)
    Docker.start(mission_id, spec)
  end

  # Converts service name to env var key:
  #   "db"    -> "DB_PORT"
  #   "cache" -> "CACHE_PORT"
  #   "web"   -> "WEB_PORT"
  defp service_env_key(service_name) do
    String.upcase(service_name) <> "_PORT"
  end
end
