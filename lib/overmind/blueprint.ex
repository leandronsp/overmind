defmodule Overmind.Blueprint do
  @moduledoc false

  alias Overmind.Blueprint.{DAG, Parser, Runner}
  alias Overmind.Mission

  @spec agents(String.t()) :: {:ok, [Parser.agent_spec()]} | {:error, term()}
  def agents(path) do
    with {:ok, content} <- File.read(path),
         {:ok, specs} <- Parser.parse(content) do
      {:ok, specs}
    end
  end

  @spec apply(String.t()) :: {:ok, %{id: String.t(), name: String.t()}} | {:error, term()}
  def apply(path) do
    with {:ok, content} <- File.read(path),
         {:ok, specs} <- Parser.parse(content),
         {:ok, sorted} <- DAG.topo_sort(specs) do
      start_runner(path, sorted)
    end
  end

  defp start_runner(path, specs) do
    id = Mission.generate_id()
    name = Mission.Name.generate()
    filename = Path.basename(path)

    spec = {Runner, id: id, name: name, filename: filename, specs: specs}

    case DynamicSupervisor.start_child(Overmind.MissionSupervisor, spec) do
      {:ok, _pid} -> {:ok, %{id: id, name: name}}
      {:error, reason} -> {:error, reason}
    end
  end
end
